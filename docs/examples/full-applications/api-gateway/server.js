/**
 * Fabstir API Gateway Server
 * REST API interface for Fabstir decentralized AI network
 */

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const { ethers } = require('ethers');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcrypt');
const { v4: uuidv4 } = require('uuid');
const Redis = require('ioredis');
const Bull = require('bull');
const winston = require('winston');
require('dotenv').config();

// Initialize logger
const logger = winston.createLogger({
    level: 'info',
    format: winston.format.json(),
    transports: [
        new winston.transports.File({ filename: 'error.log', level: 'error' }),
        new winston.transports.File({ filename: 'combined.log' }),
        new winston.transports.Console({ format: winston.format.simple() })
    ]
});

// Initialize Redis
const redis = new Redis(process.env.REDIS_URL || 'redis://localhost:6379');

// Initialize job queue
const jobQueue = new Bull('job-queue', process.env.REDIS_URL || 'redis://localhost:6379');

// Contract ABIs
const CONTRACT_ABIS = {
    JobMarketplace: require('./contracts/JobMarketplace.json').abi,
    PaymentEscrow: require('./contracts/PaymentEscrow.json').abi,
    NodeRegistry: require('./contracts/NodeRegistry.json').abi
};

// Configuration
const config = {
    port: process.env.PORT || 3000,
    jwtSecret: process.env.JWT_SECRET || 'change-me-in-production',
    rpcUrl: process.env.RPC_URL,
    privateKey: process.env.PRIVATE_KEY,
    contracts: {
        jobMarketplace: process.env.JOB_MARKETPLACE,
        paymentEscrow: process.env.PAYMENT_ESCROW,
        nodeRegistry: process.env.NODE_REGISTRY
    },
    pricing: {
        apiCall: 0.001, // $0.001 per API call
        models: {
            'gpt-4': { perToken: 0.00003, minTokens: 100 },
            'claude-2': { perToken: 0.00002, minTokens: 100 },
            'llama-2-70b': { perToken: 0.00001, minTokens: 100 },
            'mistral-7b': { perToken: 0.000005, minTokens: 50 }
        }
    },
    rateLimits: {
        free: { windowMs: 60000, max: 10 },
        basic: { windowMs: 60000, max: 100 },
        pro: { windowMs: 60000, max: 1000 },
        enterprise: { windowMs: 60000, max: 10000 }
    }
};

// Initialize blockchain connections
const provider = new ethers.JsonRpcProvider(config.rpcUrl);
const wallet = new ethers.Wallet(config.privateKey, provider);

const contracts = {
    jobMarketplace: new ethers.Contract(
        config.contracts.jobMarketplace,
        CONTRACT_ABIS.JobMarketplace,
        wallet
    ),
    paymentEscrow: new ethers.Contract(
        config.contracts.paymentEscrow,
        CONTRACT_ABIS.PaymentEscrow,
        wallet
    ),
    nodeRegistry: new ethers.Contract(
        config.contracts.nodeRegistry,
        CONTRACT_ABIS.NodeRegistry,
        wallet
    )
};

// Initialize Express app
const app = express();

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Request logging
app.use((req, res, next) => {
    logger.info({
        method: req.method,
        url: req.url,
        ip: req.ip,
        timestamp: new Date().toISOString()
    });
    next();
});

// In-memory user store (use database in production)
const users = new Map();
const apiKeys = new Map();

// Rate limiting middleware factory
function createRateLimiter(tier = 'free') {
    const limits = config.rateLimits[tier] || config.rateLimits.free;
    
    return rateLimit({
        windowMs: limits.windowMs,
        max: limits.max,
        message: 'Rate limit exceeded. Please upgrade your plan for higher limits.',
        standardHeaders: true,
        legacyHeaders: false,
        keyGenerator: (req) => req.user?.id || req.ip
    });
}

// Authentication middleware
async function authenticate(req, res, next) {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({ error: 'Missing or invalid authorization header' });
    }
    
    const token = authHeader.substring(7);
    
    // Check if it's an API key
    if (token.startsWith('fsk_')) {
        const user = apiKeys.get(token);
        if (!user) {
            return res.status(401).json({ error: 'Invalid API key' });
        }
        req.user = user;
        req.rateLimitTier = user.tier || 'free';
    } else {
        // JWT token
        try {
            const decoded = jwt.verify(token, config.jwtSecret);
            const user = users.get(decoded.userId);
            if (!user) {
                return res.status(401).json({ error: 'Invalid token' });
            }
            req.user = user;
            req.rateLimitTier = user.tier || 'free';
        } catch (error) {
            return res.status(401).json({ error: 'Invalid or expired token' });
        }
    }
    
    next();
}

// Apply rate limiting based on user tier
app.use((req, res, next) => {
    if (req.user) {
        const limiter = createRateLimiter(req.rateLimitTier);
        limiter(req, res, next);
    } else {
        next();
    }
});

// Routes

// Health check
app.get('/health', async (req, res) => {
    try {
        const blockNumber = await provider.getBlockNumber();
        res.json({
            status: 'healthy',
            version: '1.0.0',
            blockchain: {
                connected: true,
                blockNumber,
                chainId: (await provider.getNetwork()).chainId
            },
            redis: redis.status === 'ready',
            timestamp: new Date().toISOString()
        });
    } catch (error) {
        res.status(503).json({
            status: 'unhealthy',
            error: error.message
        });
    }
});

// Authentication routes
app.post('/api/auth/register', async (req, res) => {
    try {
        const { email, password, organization } = req.body;
        
        if (!email || !password) {
            return res.status(400).json({ error: 'Email and password required' });
        }
        
        // Check if user exists
        if (Array.from(users.values()).some(u => u.email === email)) {
            return res.status(409).json({ error: 'User already exists' });
        }
        
        // Create user
        const userId = uuidv4();
        const hashedPassword = await bcrypt.hash(password, 10);
        const apiKey = `fsk_${uuidv4().replace(/-/g, '')}`;
        
        const user = {
            id: userId,
            email,
            password: hashedPassword,
            organization,
            apiKey,
            tier: 'free',
            balance: '0',
            createdAt: new Date().toISOString()
        };
        
        users.set(userId, user);
        apiKeys.set(apiKey, user);
        
        // Store in Redis for persistence
        await redis.set(`user:${userId}`, JSON.stringify(user));
        await redis.set(`apikey:${apiKey}`, userId);
        
        res.status(201).json({
            id: userId,
            email,
            apiKey,
            tier: user.tier
        });
        
    } catch (error) {
        logger.error('Registration error:', error);
        res.status(500).json({ error: 'Registration failed' });
    }
});

app.post('/api/auth/login', async (req, res) => {
    try {
        const { email, password } = req.body;
        
        // Find user
        const user = Array.from(users.values()).find(u => u.email === email);
        if (!user) {
            return res.status(401).json({ error: 'Invalid credentials' });
        }
        
        // Verify password
        const validPassword = await bcrypt.compare(password, user.password);
        if (!validPassword) {
            return res.status(401).json({ error: 'Invalid credentials' });
        }
        
        // Generate JWT
        const token = jwt.sign(
            { userId: user.id, email: user.email },
            config.jwtSecret,
            { expiresIn: '24h' }
        );
        
        res.json({
            token,
            apiKey: user.apiKey,
            user: {
                id: user.id,
                email: user.email,
                tier: user.tier,
                balance: user.balance
            }
        });
        
    } catch (error) {
        logger.error('Login error:', error);
        res.status(500).json({ error: 'Login failed' });
    }
});

// Model endpoints
app.get('/api/v1/models', authenticate, async (req, res) => {
    try {
        const models = Object.entries(config.pricing.models).map(([id, pricing]) => ({
            id,
            object: 'model',
            created: 1677649420,
            owned_by: 'community',
            permission: ['query'],
            root: id,
            parent: null,
            pricing: {
                per_token: pricing.perToken,
                min_tokens: pricing.minTokens
            }
        }));
        
        res.json({
            object: 'list',
            data: models
        });
        
    } catch (error) {
        logger.error('Models error:', error);
        res.status(500).json({ error: 'Failed to fetch models' });
    }
});

// Completion endpoint (OpenAI compatible)
app.post('/api/v1/completions', authenticate, async (req, res) => {
    try {
        const {
            model,
            prompt,
            max_tokens = 1000,
            temperature = 0.7,
            top_p = 1,
            n = 1,
            stream = false,
            stop = null
        } = req.body;
        
        if (!model || !prompt) {
            return res.status(400).json({ error: 'Model and prompt required' });
        }
        
        // Validate model
        if (!config.pricing.models[model]) {
            return res.status(400).json({ error: 'Invalid model' });
        }
        
        // Create job ID
        const jobId = `job_${uuidv4().replace(/-/g, '').substring(0, 12)}`;
        
        // Calculate cost
        const estimatedTokens = Math.min(prompt.length + 500, max_tokens);
        const costPerToken = config.pricing.models[model].perToken;
        const jobCost = costPerToken * estimatedTokens;
        
        // Check user balance
        const userBalance = parseFloat(req.user.balance);
        if (userBalance < jobCost) {
            return res.status(402).json({ 
                error: 'Insufficient balance',
                required: jobCost,
                balance: userBalance
            });
        }
        
        // Queue the job
        const job = await jobQueue.add('process-completion', {
            jobId,
            userId: req.user.id,
            model,
            prompt,
            max_tokens,
            temperature,
            top_p,
            n,
            stop,
            cost: jobCost
        });
        
        // If not streaming, wait for completion
        if (!stream) {
            const result = await job.finished();
            
            res.json({
                id: jobId,
                object: 'text_completion',
                created: Math.floor(Date.now() / 1000),
                model,
                choices: [{
                    text: result.text,
                    index: 0,
                    logprobs: null,
                    finish_reason: 'stop'
                }],
                usage: {
                    prompt_tokens: result.promptTokens,
                    completion_tokens: result.completionTokens,
                    total_tokens: result.totalTokens
                }
            });
        } else {
            // Return job ID for streaming
            res.json({
                id: jobId,
                object: 'text_completion',
                created: Math.floor(Date.now() / 1000),
                model,
                stream: true
            });
        }
        
    } catch (error) {
        logger.error('Completion error:', error);
        res.status(500).json({ error: 'Completion request failed' });
    }
});

// Job status endpoint
app.get('/api/v1/jobs/:id', authenticate, async (req, res) => {
    try {
        const jobId = req.params.id;
        
        // Get job from Redis
        const jobData = await redis.get(`job:${jobId}`);
        if (!jobData) {
            return res.status(404).json({ error: 'Job not found' });
        }
        
        const job = JSON.parse(jobData);
        
        // Verify ownership
        if (job.userId !== req.user.id) {
            return res.status(403).json({ error: 'Access denied' });
        }
        
        res.json(job);
        
    } catch (error) {
        logger.error('Job status error:', error);
        res.status(500).json({ error: 'Failed to fetch job status' });
    }
});

// Account endpoints
app.get('/api/v1/account', authenticate, async (req, res) => {
    try {
        const usage = await calculateUsage(req.user.id);
        
        res.json({
            id: req.user.id,
            email: req.user.email,
            organization: req.user.organization,
            tier: req.user.tier,
            balance: req.user.balance,
            usage: {
                current_month: usage.currentMonth,
                last_month: usage.lastMonth,
                total: usage.total
            },
            limits: config.rateLimits[req.user.tier] || config.rateLimits.free,
            created_at: req.user.createdAt
        });
        
    } catch (error) {
        logger.error('Account error:', error);
        res.status(500).json({ error: 'Failed to fetch account info' });
    }
});

app.post('/api/v1/account/deposit', authenticate, async (req, res) => {
    try {
        const { amount } = req.body;
        
        if (!amount || parseFloat(amount) <= 0) {
            return res.status(400).json({ error: 'Invalid amount' });
        }
        
        // In production, integrate with payment processor
        // For demo, just update balance
        const currentBalance = parseFloat(req.user.balance);
        const newBalance = currentBalance + parseFloat(amount);
        
        req.user.balance = newBalance.toString();
        await redis.set(`user:${req.user.id}`, JSON.stringify(req.user));
        
        res.json({
            success: true,
            balance: newBalance.toString(),
            transaction_id: `txn_${uuidv4()}`
        });
        
    } catch (error) {
        logger.error('Deposit error:', error);
        res.status(500).json({ error: 'Deposit failed' });
    }
});

// Webhook management
app.post('/api/v1/webhooks', authenticate, async (req, res) => {
    try {
        const { url, events, secret } = req.body;
        
        if (!url || !events || !Array.isArray(events)) {
            return res.status(400).json({ error: 'Invalid webhook configuration' });
        }
        
        const webhookId = `whk_${uuidv4().replace(/-/g, '')}`;
        const webhook = {
            id: webhookId,
            userId: req.user.id,
            url,
            events,
            secret: secret || `whsec_${uuidv4().replace(/-/g, '')}`,
            active: true,
            createdAt: new Date().toISOString()
        };
        
        await redis.set(`webhook:${webhookId}`, JSON.stringify(webhook));
        
        res.status(201).json(webhook);
        
    } catch (error) {
        logger.error('Webhook error:', error);
        res.status(500).json({ error: 'Failed to create webhook' });
    }
});

// Job queue processor
jobQueue.process('process-completion', async (job) => {
    const { jobId, userId, model, prompt, max_tokens, cost } = job.data;
    
    try {
        logger.info(`Processing job ${jobId} for user ${userId}`);
        
        // Deduct cost from user balance
        const user = users.get(userId);
        user.balance = (parseFloat(user.balance) - cost).toString();
        await redis.set(`user:${userId}`, JSON.stringify(user));
        
        // Post job to blockchain
        const inputData = ethers.AbiCoder.defaultAbiCoder().encode(
            ['string', 'uint256', 'string'],
            [prompt, max_tokens, 'api-gateway-v1']
        );
        
        const payment = ethers.parseEther(cost.toString());
        const tx = await contracts.jobMarketplace.postJob(
            model,
            max_tokens,
            3600, // 1 hour deadline
            inputData,
            { value: payment }
        );
        
        const receipt = await tx.wait();
        
        // Extract blockchain job ID
        const event = receipt.logs
            .map(log => {
                try {
                    return contracts.jobMarketplace.interface.parseLog(log);
                } catch {
                    return null;
                }
            })
            .find(e => e && e.name === 'JobPosted');
        
        const blockchainJobId = event.args[0];
        
        // Store job mapping
        await redis.set(`job:${jobId}`, JSON.stringify({
            id: jobId,
            userId,
            blockchainJobId: blockchainJobId.toString(),
            status: 'processing',
            model,
            cost,
            createdAt: new Date().toISOString()
        }));
        
        // Monitor job completion
        const result = await monitorJobCompletion(blockchainJobId);
        
        // Update job with result
        const completedJob = {
            id: jobId,
            userId,
            blockchainJobId: blockchainJobId.toString(),
            status: 'completed',
            model,
            cost,
            result: {
                text: result.output,
                promptTokens: result.promptTokens,
                completionTokens: result.completionTokens,
                totalTokens: result.totalTokens
            },
            createdAt: job.data.createdAt,
            completedAt: new Date().toISOString()
        };
        
        await redis.set(`job:${jobId}`, JSON.stringify(completedJob));
        
        // Send webhook if configured
        await sendWebhook(userId, 'job.completed', completedJob);
        
        return completedJob.result;
        
    } catch (error) {
        logger.error(`Job ${jobId} failed:`, error);
        
        // Refund user
        const user = users.get(userId);
        user.balance = (parseFloat(user.balance) + cost).toString();
        await redis.set(`user:${userId}`, JSON.stringify(user));
        
        // Update job status
        await redis.set(`job:${jobId}`, JSON.stringify({
            id: jobId,
            userId,
            status: 'failed',
            error: error.message,
            createdAt: job.data.createdAt,
            failedAt: new Date().toISOString()
        }));
        
        // Send webhook
        await sendWebhook(userId, 'job.failed', { jobId, error: error.message });
        
        throw error;
    }
});

// Monitor blockchain job completion
async function monitorJobCompletion(blockchainJobId) {
    return new Promise((resolve, reject) => {
        const checkInterval = setInterval(async () => {
            try {
                const job = await contracts.jobMarketplace.getJob(blockchainJobId);
                
                if (job.status === 2) { // Completed
                    clearInterval(checkInterval);
                    
                    // Decode output
                    const [output, tokensUsed] = ethers.AbiCoder.defaultAbiCoder().decode(
                        ['string', 'uint256', 'uint256', 'string'],
                        job.outputData
                    );
                    
                    resolve({
                        output,
                        promptTokens: Math.floor(tokensUsed * 0.3),
                        completionTokens: Math.floor(tokensUsed * 0.7),
                        totalTokens: tokensUsed
                    });
                } else if (job.status === 3) { // Cancelled
                    clearInterval(checkInterval);
                    reject(new Error('Job cancelled'));
                }
            } catch (error) {
                clearInterval(checkInterval);
                reject(error);
            }
        }, 5000); // Check every 5 seconds
        
        // Timeout after 2 hours
        setTimeout(() => {
            clearInterval(checkInterval);
            reject(new Error('Job timeout'));
        }, 2 * 60 * 60 * 1000);
    });
}

// Calculate usage for user
async function calculateUsage(userId) {
    // In production, query from database
    // For demo, return mock data
    return {
        currentMonth: '0.5678',
        lastMonth: '0.9012',
        total: '2.3456'
    };
}

// Send webhook
async function sendWebhook(userId, event, data) {
    try {
        // Get user webhooks
        const webhookKeys = await redis.keys(`webhook:*`);
        
        for (const key of webhookKeys) {
            const webhookData = await redis.get(key);
            const webhook = JSON.parse(webhookData);
            
            if (webhook.userId === userId && webhook.events.includes(event) && webhook.active) {
                // Send webhook (in production, use a queue)
                await fetch(webhook.url, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-Webhook-Signature': generateWebhookSignature(data, webhook.secret)
                    },
                    body: JSON.stringify({
                        event,
                        data,
                        timestamp: new Date().toISOString()
                    })
                });
            }
        }
    } catch (error) {
        logger.error('Webhook error:', error);
    }
}

// Generate webhook signature
function generateWebhookSignature(data, secret) {
    const crypto = require('crypto');
    const timestamp = Math.floor(Date.now() / 1000);
    const payload = `${timestamp}.${JSON.stringify(data)}`;
    const signature = crypto.createHmac('sha256', secret).update(payload).digest('hex');
    return `t=${timestamp},v1=${signature}`;
}

// Error handling middleware
app.use((err, req, res, next) => {
    logger.error(err.stack);
    res.status(500).json({ 
        error: 'Internal server error',
        message: process.env.NODE_ENV === 'development' ? err.message : undefined
    });
});

// 404 handler
app.use((req, res) => {
    res.status(404).json({ error: 'Endpoint not found' });
});

// Load users from Redis on startup
async function loadUsers() {
    try {
        const userKeys = await redis.keys('user:*');
        for (const key of userKeys) {
            const userData = await redis.get(key);
            const user = JSON.parse(userData);
            users.set(user.id, user);
            apiKeys.set(user.apiKey, user);
        }
        logger.info(`Loaded ${users.size} users from Redis`);
    } catch (error) {
        logger.error('Failed to load users:', error);
    }
}

// Start server
async function start() {
    await loadUsers();
    
    const server = app.listen(config.port, () => {
        logger.info(`🚀 Fabstir API Gateway running on port ${config.port}`);
        logger.info(`📡 Connected to chain ID: ${config.chainId}`);
        logger.info(`🔗 Job Marketplace: ${config.contracts.jobMarketplace}`);
    });
    
    // Graceful shutdown
    process.on('SIGTERM', async () => {
        logger.info('SIGTERM received, shutting down gracefully...');
        
        server.close(() => {
            logger.info('HTTP server closed');
        });
        
        await jobQueue.close();
        await redis.quit();
        
        process.exit(0);
    });
}

// Start the server
start().catch(error => {
    logger.error('Failed to start:', error);
    process.exit(1);
});

module.exports = app;