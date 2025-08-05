# Building on Fabstir Guide

This guide shows how to build complete applications and services on top of the Fabstir marketplace, from simple integrations to complex AI-powered platforms.

## Prerequisites

- Understanding of [Contract Integration](contract-integration.md)
- Familiarity with [SDK Usage](sdk-usage.md)
- Web development experience
- Basic understanding of AI/ML concepts

## Architecture Patterns

### Common Application Architectures

```
1. Direct Integration
   User → Your App → Fabstir SDK → Contracts

2. Backend Service
   User → Your App → Your API → Fabstir SDK → Contracts

3. Hybrid Approach
   User → Your App → Your API → Queue → Workers → Fabstir
              ↓
         Direct SDK calls for urgent tasks
```

## Example Applications

### 1. AI Writing Assistant

A complete web application that helps users generate content using various AI models.

#### Backend API (Node.js/Express)
```javascript
import express from 'express';
import { FabstirSDK, Network } from '@fabstir/sdk';
import { createClient } from 'redis';
import { v4 as uuidv4 } from 'uuid';

const app = express();
const sdk = new FabstirSDK({
    network: Network.BASE_MAINNET,
    privateKey: process.env.WALLET_PRIVATE_KEY
});

const redis = createClient({ url: process.env.REDIS_URL });
await redis.connect();

// Middleware
app.use(express.json());
app.use(authMiddleware);

// Content generation endpoint
app.post('/api/generate', async (req, res) => {
    try {
        const { 
            type, // 'blog', 'email', 'code', 'summary'
            prompt,
            style,
            length,
            userId
        } = req.body;
        
        // Build enhanced prompt
        const enhancedPrompt = buildPrompt(type, prompt, style, length);
        
        // Select appropriate model
        const modelConfig = selectModel(type, length);
        
        // Create job
        const job = await sdk.jobs.create({
            modelId: modelConfig.modelId,
            prompt: enhancedPrompt,
            payment: modelConfig.payment,
            maxTokens: modelConfig.maxTokens,
            temperature: modelConfig.temperature,
            metadata: {
                userId,
                type,
                requestId: uuidv4()
            }
        });
        
        // Store job mapping
        await redis.set(`user:${userId}:job:${job.id}`, JSON.stringify({
            type,
            createdAt: Date.now(),
            status: 'pending'
        }));
        
        // Return job ID for polling
        res.json({
            jobId: job.id,
            estimatedTime: modelConfig.estimatedTime,
            cost: modelConfig.payment
        });
        
    } catch (error) {
        console.error('Generation error:', error);
        res.status(500).json({ error: 'Failed to create job' });
    }
});

// Result polling endpoint
app.get('/api/result/:jobId', async (req, res) => {
    try {
        const { jobId } = req.params;
        const userId = req.user.id;
        
        // Verify ownership
        const jobData = await redis.get(`user:${userId}:job:${jobId}`);
        if (!jobData) {
            return res.status(404).json({ error: 'Job not found' });
        }
        
        // Check job status
        const job = await sdk.jobs.get(jobId);
        
        if (job.status === 'completed') {
            const result = await sdk.jobs.getResult(jobId);
            
            // Post-process result
            const processed = await postProcessResult(
                result.data,
                JSON.parse(jobData).type
            );
            
            // Cache result
            await redis.setex(
                `result:${jobId}`,
                3600,
                JSON.stringify(processed)
            );
            
            res.json({
                status: 'completed',
                result: processed
            });
        } else {
            res.json({
                status: job.status,
                progress: estimateProgress(job)
            });
        }
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Helper functions
function buildPrompt(type, userPrompt, style, length) {
    const templates = {
        blog: `Write a ${length} blog post about: ${userPrompt}. Style: ${style}. Include an engaging introduction, clear sections, and a conclusion.`,
        email: `Write a professional ${length} email: ${userPrompt}. Tone: ${style}.`,
        code: `Write clean, well-commented code: ${userPrompt}. Include error handling and best practices.`,
        summary: `Summarize the following in ${length}: ${userPrompt}. Focus on key points.`
    };
    
    return templates[type] || userPrompt;
}

function selectModel(type, length) {
    const configs = {
        blog: {
            short: { modelId: 'gpt-3.5-turbo', payment: '0.002', maxTokens: 500 },
            medium: { modelId: 'gpt-4', payment: '0.01', maxTokens: 1500 },
            long: { modelId: 'gpt-4', payment: '0.02', maxTokens: 3000 }
        },
        code: {
            modelId: 'codellama-34b',
            payment: '0.008',
            maxTokens: 2000,
            temperature: 0.2
        }
    };
    
    return configs[type]?.[length] || configs[type] || {
        modelId: 'gpt-3.5-turbo',
        payment: '0.005',
        maxTokens: 1000
    };
}

async function postProcessResult(result, type) {
    // Type-specific processing
    if (type === 'code') {
        return {
            code: extractCode(result),
            explanation: extractExplanation(result),
            language: detectLanguage(result)
        };
    } else if (type === 'blog') {
        return {
            title: extractTitle(result),
            content: formatBlogContent(result),
            metadata: extractMetadata(result)
        };
    }
    
    return { content: result };
}

// Background job processor
class JobProcessor {
    constructor(sdk, redis) {
        this.sdk = sdk;
        this.redis = redis;
    }
    
    async start() {
        // Subscribe to job events
        this.sdk.events.subscribe({
            onJobCompleted: async ({ jobId, result }) => {
                await this.handleCompletion(jobId, result);
            }
        });
        
        // Process retry queue
        setInterval(() => this.processRetryQueue(), 60000);
    }
    
    async handleCompletion(jobId, result) {
        try {
            // Get job metadata
            const jobData = await this.redis.get(`job:${jobId}:metadata`);
            if (!jobData) return;
            
            const { userId, type, webhookUrl } = JSON.parse(jobData);
            
            // Verify result quality
            const verification = await this.sdk.jobs.verifyResult(jobId);
            
            if (verification.qualityScore > 0.7) {
                // Accept result
                await this.sdk.jobs.acceptResult(jobId);
                
                // Send webhook notification
                if (webhookUrl) {
                    await this.sendWebhook(webhookUrl, {
                        jobId,
                        status: 'completed',
                        result: result.data,
                        quality: verification.qualityScore
                    });
                }
                
                // Update user statistics
                await this.updateUserStats(userId, {
                    jobsCompleted: 1,
                    tokensUsed: result.tokensUsed,
                    cost: result.cost
                });
                
            } else {
                // Queue for retry with different model
                await this.queueRetry(jobId, jobData);
            }
            
        } catch (error) {
            console.error('Completion handler error:', error);
        }
    }
}

// Start background processor
const processor = new JobProcessor(sdk, redis);
processor.start();

app.listen(3000, () => {
    console.log('AI Writing Assistant API running on port 3000');
});
```

#### Frontend React Application
```jsx
import React, { useState, useEffect } from 'react';
import { FabstirSDK, Network } from '@fabstir/sdk';
import axios from 'axios';

// Initialize SDK for read operations
const sdk = new FabstirSDK({
    network: Network.BASE_MAINNET
});

function WritingAssistant() {
    const [content, setContent] = useState('');
    const [generating, setGenerating] = useState(false);
    const [currentJob, setCurrentJob] = useState(null);
    const [progress, setProgress] = useState(0);
    const [history, setHistory] = useState([]);
    
    useEffect(() => {
        loadHistory();
    }, []);
    
    const generateContent = async (type, prompt, options) => {
        try {
            setGenerating(true);
            setProgress(0);
            
            // Call backend API
            const response = await axios.post('/api/generate', {
                type,
                prompt,
                style: options.style,
                length: options.length
            });
            
            setCurrentJob(response.data.jobId);
            
            // Poll for results
            const result = await pollForResult(response.data.jobId);
            
            setContent(result.content);
            addToHistory({
                type,
                prompt,
                result: result.content,
                cost: response.data.cost
            });
            
        } catch (error) {
            console.error('Generation error:', error);
            alert('Failed to generate content');
        } finally {
            setGenerating(false);
            setCurrentJob(null);
        }
    };
    
    const pollForResult = async (jobId) => {
        const maxAttempts = 60;
        let attempts = 0;
        
        while (attempts < maxAttempts) {
            const response = await axios.get(`/api/result/${jobId}`);
            
            if (response.data.status === 'completed') {
                return response.data.result;
            }
            
            // Update progress
            setProgress(response.data.progress || (attempts / maxAttempts * 100));
            
            // Wait before next poll
            await new Promise(resolve => setTimeout(resolve, 2000));
            attempts++;
        }
        
        throw new Error('Generation timeout');
    };
    
    const loadHistory = async () => {
        try {
            const response = await axios.get('/api/history');
            setHistory(response.data);
        } catch (error) {
            console.error('Failed to load history');
        }
    };
    
    return (
        <div className="writing-assistant">
            <h1>AI Writing Assistant</h1>
            
            <ContentGenerator
                onGenerate={generateContent}
                disabled={generating}
            />
            
            {generating && (
                <ProgressBar
                    progress={progress}
                    jobId={currentJob}
                />
            )}
            
            {content && (
                <ContentDisplay
                    content={content}
                    onEdit={setContent}
                    onSave={() => saveContent(content)}
                />
            )}
            
            <History
                items={history}
                onSelect={(item) => setContent(item.result)}
            />
        </div>
    );
}

function ContentGenerator({ onGenerate, disabled }) {
    const [type, setType] = useState('blog');
    const [prompt, setPrompt] = useState('');
    const [options, setOptions] = useState({
        style: 'professional',
        length: 'medium'
    });
    
    const handleSubmit = (e) => {
        e.preventDefault();
        onGenerate(type, prompt, options);
    };
    
    return (
        <form onSubmit={handleSubmit}>
            <select
                value={type}
                onChange={(e) => setType(e.target.value)}
                disabled={disabled}
            >
                <option value="blog">Blog Post</option>
                <option value="email">Email</option>
                <option value="code">Code</option>
                <option value="summary">Summary</option>
            </select>
            
            <textarea
                value={prompt}
                onChange={(e) => setPrompt(e.target.value)}
                placeholder="Describe what you want to generate..."
                disabled={disabled}
                required
            />
            
            <div className="options">
                <select
                    value={options.style}
                    onChange={(e) => setOptions({...options, style: e.target.value})}
                >
                    <option value="professional">Professional</option>
                    <option value="casual">Casual</option>
                    <option value="creative">Creative</option>
                    <option value="technical">Technical</option>
                </select>
                
                <select
                    value={options.length}
                    onChange={(e) => setOptions({...options, length: e.target.value})}
                >
                    <option value="short">Short</option>
                    <option value="medium">Medium</option>
                    <option value="long">Long</option>
                </select>
            </div>
            
            <button type="submit" disabled={disabled}>
                {disabled ? 'Generating...' : 'Generate'}
            </button>
        </form>
    );
}

// Real-time cost estimator
function CostEstimator({ type, length }) {
    const [estimate, setEstimate] = useState(null);
    
    useEffect(() => {
        estimateCost();
    }, [type, length]);
    
    const estimateCost = async () => {
        try {
            const response = await axios.get('/api/estimate', {
                params: { type, length }
            });
            setEstimate(response.data);
        } catch (error) {
            console.error('Estimation failed');
        }
    };
    
    if (!estimate) return null;
    
    return (
        <div className="cost-estimate">
            <span>Estimated cost: {estimate.cost} ETH</span>
            <span>Time: ~{estimate.time}s</span>
            <span>Model: {estimate.model}</span>
        </div>
    );
}
```

### 2. Decentralized AI API Gateway

Build an API gateway that provides simple REST access to Fabstir's AI models.

```javascript
import express from 'express';
import { FabstirSDK } from '@fabstir/sdk';
import rateLimit from 'express-rate-limit';
import { LRUCache } from 'lru-cache';
import jwt from 'jsonwebtoken';

class AIGateway {
    constructor() {
        this.app = express();
        this.sdk = new FabstirSDK({
            network: process.env.NETWORK,
            privateKey: process.env.PRIVATE_KEY
        });
        
        this.cache = new LRUCache({
            max: 1000,
            ttl: 1000 * 60 * 60 // 1 hour
        });
        
        this.setupMiddleware();
        this.setupRoutes();
        this.setupWebsockets();
    }
    
    setupMiddleware() {
        // Rate limiting per API key
        this.rateLimiter = rateLimit({
            windowMs: 60 * 1000, // 1 minute
            max: (req) => {
                const tier = req.user?.tier || 'free';
                return {
                    free: 10,
                    basic: 100,
                    premium: 1000
                }[tier];
            },
            keyGenerator: (req) => req.user?.apiKey || req.ip
        });
        
        this.app.use(express.json({ limit: '10mb' }));
        this.app.use(this.authenticate);
        this.app.use(this.rateLimiter);
        this.app.use(this.logRequest);
    }
    
    setupRoutes() {
        // Simple inference endpoint
        this.app.post('/v1/inference', async (req, res) => {
            try {
                const { model, prompt, parameters = {} } = req.body;
                
                // Check cache
                const cacheKey = this.getCacheKey(model, prompt, parameters);
                const cached = this.cache.get(cacheKey);
                if (cached) {
                    return res.json({
                        result: cached,
                        cached: true
                    });
                }
                
                // Validate request
                const validation = this.validateRequest(model, prompt, parameters);
                if (!validation.valid) {
                    return res.status(400).json({ error: validation.error });
                }
                
                // Calculate pricing
                const pricing = await this.calculatePricing(
                    model,
                    prompt,
                    req.user.tier
                );
                
                // Check user balance
                if (!await this.checkBalance(req.user, pricing.total)) {
                    return res.status(402).json({
                        error: 'Insufficient balance',
                        required: pricing.total
                    });
                }
                
                // Create job
                const job = await this.sdk.jobs.create({
                    modelId: model,
                    prompt: prompt,
                    payment: pricing.basePrice,
                    ...parameters,
                    metadata: {
                        userId: req.user.id,
                        apiKey: req.user.apiKey
                    }
                });
                
                // Deduct from balance
                await this.deductBalance(req.user, pricing.total);
                
                // Wait for result (with timeout)
                const result = await this.waitForResult(job.id, 60000);
                
                // Cache result
                this.cache.set(cacheKey, result);
                
                // Track usage
                await this.trackUsage(req.user, {
                    model,
                    tokens: result.tokensUsed,
                    cost: pricing.total
                });
                
                res.json({
                    result: result.data,
                    usage: {
                        tokens: result.tokensUsed,
                        cost: pricing.total
                    }
                });
                
            } catch (error) {
                console.error('Inference error:', error);
                res.status(500).json({ error: error.message });
            }
        });
        
        // Batch inference
        this.app.post('/v1/batch', async (req, res) => {
            try {
                const { requests } = req.body;
                
                if (!Array.isArray(requests) || requests.length > 100) {
                    return res.status(400).json({
                        error: 'Invalid batch size (max 100)'
                    });
                }
                
                // Create batch ID
                const batchId = this.generateBatchId();
                
                // Queue batch job
                await this.queueBatch(batchId, requests, req.user);
                
                res.json({
                    batchId,
                    status: 'queued',
                    count: requests.length,
                    webhookUrl: `/v1/batch/${batchId}/status`
                });
                
            } catch (error) {
                res.status(500).json({ error: error.message });
            }
        });
        
        // Model information
        this.app.get('/v1/models', async (req, res) => {
            try {
                const models = await this.getAvailableModels();
                res.json({ models });
            } catch (error) {
                res.status(500).json({ error: error.message });
            }
        });
        
        // User dashboard
        this.app.get('/v1/usage', async (req, res) => {
            try {
                const usage = await this.getUserUsage(req.user);
                res.json(usage);
            } catch (error) {
                res.status(500).json({ error: error.message });
            }
        });
    }
    
    setupWebsockets() {
        // Real-time streaming for long-running jobs
        this.io = require('socket.io')(this.server);
        
        this.io.use(async (socket, next) => {
            try {
                const token = socket.handshake.auth.token;
                const user = await this.verifyToken(token);
                socket.user = user;
                next();
            } catch (error) {
                next(new Error('Authentication failed'));
            }
        });
        
        this.io.on('connection', (socket) => {
            console.log('Client connected:', socket.user.id);
            
            socket.on('stream', async (data) => {
                try {
                    const { model, prompt, parameters } = data;
                    
                    // Create streaming job
                    const job = await this.createStreamingJob(
                        model,
                        prompt,
                        parameters,
                        socket.user
                    );
                    
                    // Stream results
                    this.streamResults(job.id, socket);
                    
                } catch (error) {
                    socket.emit('error', error.message);
                }
            });
        });
    }
    
    // Helper methods
    async authenticate(req, res, next) {
        const apiKey = req.headers['x-api-key'];
        
        if (!apiKey) {
            return res.status(401).json({ error: 'API key required' });
        }
        
        try {
            const user = await this.getUserByApiKey(apiKey);
            if (!user) {
                return res.status(401).json({ error: 'Invalid API key' });
            }
            
            req.user = user;
            next();
        } catch (error) {
            res.status(500).json({ error: 'Authentication failed' });
        }
    }
    
    async calculatePricing(model, prompt, tier) {
        const basePrices = {
            'gpt-4': 0.03,
            'gpt-3.5-turbo': 0.002,
            'llama-2-70b': 0.01,
            'codellama-34b': 0.008
        };
        
        const tierMultipliers = {
            free: 2.0,
            basic: 1.5,
            premium: 1.2
        };
        
        const basePrice = basePrices[model] || 0.01;
        const multiplier = tierMultipliers[tier] || 2.0;
        const platformFee = basePrice * 0.2; // 20% platform fee
        
        return {
            basePrice: basePrice.toFixed(4),
            platformFee: platformFee.toFixed(4),
            total: ((basePrice + platformFee) * multiplier).toFixed(4)
        };
    }
    
    async getAvailableModels() {
        // Query nodes for supported models
        const activeNodes = await this.sdk.nodes.query({ active: true });
        const modelSupport = new Map();
        
        for (const node of activeNodes) {
            for (const model of node.models) {
                const current = modelSupport.get(model) || {
                    name: model,
                    nodes: 0,
                    avgPrice: 0,
                    availability: 0
                };
                
                current.nodes++;
                modelSupport.set(model, current);
            }
        }
        
        // Calculate availability scores
        return Array.from(modelSupport.values()).map(model => ({
            ...model,
            availability: Math.min(100, model.nodes * 20) // Simple scoring
        }));
    }
    
    async queueBatch(batchId, requests, user) {
        // Store batch in database
        await this.db.batch.create({
            id: batchId,
            userId: user.id,
            requests: requests,
            status: 'queued',
            createdAt: Date.now()
        });
        
        // Process asynchronously
        setImmediate(() => this.processBatch(batchId));
    }
    
    async processBatch(batchId) {
        try {
            const batch = await this.db.batch.findById(batchId);
            const results = [];
            
            // Update status
            await this.db.batch.update(batchId, { status: 'processing' });
            
            // Process each request
            for (const request of batch.requests) {
                try {
                    const job = await this.sdk.jobs.create({
                        modelId: request.model,
                        prompt: request.prompt,
                        payment: await this.getBatchPrice(request.model),
                        ...request.parameters
                    });
                    
                    const result = await this.sdk.jobs.waitForResult(job.id);
                    
                    results.push({
                        requestId: request.id,
                        success: true,
                        result: result.data
                    });
                    
                } catch (error) {
                    results.push({
                        requestId: request.id,
                        success: false,
                        error: error.message
                    });
                }
            }
            
            // Update batch with results
            await this.db.batch.update(batchId, {
                status: 'completed',
                results: results,
                completedAt: Date.now()
            });
            
            // Send webhook if configured
            if (batch.webhookUrl) {
                await this.sendWebhook(batch.webhookUrl, {
                    batchId,
                    status: 'completed',
                    results
                });
            }
            
        } catch (error) {
            console.error('Batch processing error:', error);
            await this.db.batch.update(batchId, {
                status: 'failed',
                error: error.message
            });
        }
    }
    
    getCacheKey(model, prompt, parameters) {
        return `${model}:${Buffer.from(prompt).toString('base64').substring(0, 20)}:${JSON.stringify(parameters)}`;
    }
    
    start(port = 3000) {
        this.server = this.app.listen(port, () => {
            console.log(`AI Gateway running on port ${port}`);
        });
    }
}

// Start the gateway
const gateway = new AIGateway();
gateway.start();
```

### 3. AI-Powered Discord Bot

Create a Discord bot that uses Fabstir for AI responses.

```javascript
import { Client, GatewayIntentBits } from 'discord.js';
import { FabstirSDK } from '@fabstir/sdk';
import { createClient } from 'redis';

class FabstirBot {
    constructor() {
        this.client = new Client({
            intents: [
                GatewayIntentBits.Guilds,
                GatewayIntentBits.GuildMessages,
                GatewayIntentBits.MessageContent
            ]
        });
        
        this.sdk = new FabstirSDK({
            network: process.env.FABSTIR_NETWORK,
            privateKey: process.env.FABSTIR_PRIVATE_KEY
        });
        
        this.redis = createClient({ url: process.env.REDIS_URL });
        this.setupCommands();
        this.setupEventHandlers();
    }
    
    setupCommands() {
        this.commands = new Map([
            ['!ask', this.handleAsk.bind(this)],
            ['!image', this.handleImage.bind(this)],
            ['!code', this.handleCode.bind(this)],
            ['!summarize', this.handleSummarize.bind(this)],
            ['!help', this.handleHelp.bind(this)]
        ]);
    }
    
    setupEventHandlers() {
        this.client.on('ready', () => {
            console.log(`Bot logged in as ${this.client.user.tag}`);
            this.client.user.setActivity('AI powered by Fabstir');
        });
        
        this.client.on('messageCreate', async (message) => {
            if (message.author.bot) return;
            
            // Check for commands
            const [command, ...args] = message.content.split(' ');
            const handler = this.commands.get(command.toLowerCase());
            
            if (handler) {
                await handler(message, args.join(' '));
            } else if (message.mentions.has(this.client.user)) {
                // Respond to mentions
                await this.handleMention(message);
            }
        });
        
        this.client.on('interactionCreate', async (interaction) => {
            if (!interaction.isChatInputCommand()) return;
            
            await this.handleSlashCommand(interaction);
        });
    }
    
    async handleAsk(message, prompt) {
        if (!prompt) {
            return message.reply('Please provide a question!');
        }
        
        try {
            // Check rate limit
            if (!await this.checkRateLimit(message.author.id)) {
                return message.reply('You\'re sending requests too quickly!');
            }
            
            // Send initial response
            const reply = await message.reply('🤔 Thinking...');
            
            // Create job
            const job = await this.sdk.jobs.create({
                modelId: 'gpt-4',
                prompt: this.buildPrompt('question', prompt, message),
                payment: '0.005',
                maxTokens: 500
            });
            
            // Track for user
            await this.trackUserJob(message.author.id, job.id);
            
            // Wait for result
            const result = await this.sdk.jobs.waitForResult(job.id, 30000);
            
            // Update response
            await reply.edit(this.formatResponse(result.data));
            
            // Add cost reaction
            await reply.react('💰');
            await this.addCostInfo(reply, '0.005');
            
        } catch (error) {
            console.error('Ask command error:', error);
            message.reply('Sorry, I encountered an error processing your request.');
        }
    }
    
    async handleImage(message, prompt) {
        if (!prompt) {
            return message.reply('Please describe the image you want!');
        }
        
        try {
            // Check if user has image generation permissions
            if (!await this.hasImagePermissions(message.guild.id, message.author.id)) {
                return message.reply('You don\'t have permission to generate images.');
            }
            
            const reply = await message.reply('🎨 Generating image...');
            
            // Enhanced prompt for better results
            const enhancedPrompt = `${prompt}, high quality, detailed, professional`;
            
            const job = await this.sdk.jobs.create({
                modelId: 'stable-diffusion-xl',
                prompt: enhancedPrompt,
                payment: '0.01',
                parameters: {
                    width: 1024,
                    height: 1024,
                    steps: 30,
                    guidance_scale: 7.5
                }
            });
            
            const result = await this.sdk.jobs.waitForResult(job.id, 60000);
            
            // Upload image to Discord
            const imageBuffer = Buffer.from(result.data, 'base64');
            
            await reply.edit({
                content: `Here's your image for: "${prompt}"`,
                files: [{
                    attachment: imageBuffer,
                    name: 'generated-image.png'
                }]
            });
            
        } catch (error) {
            console.error('Image command error:', error);
            message.reply('Failed to generate image.');
        }
    }
    
    async handleCode(message, request) {
        try {
            const reply = await message.reply('💻 Writing code...');
            
            const job = await this.sdk.jobs.create({
                modelId: 'codellama-34b',
                prompt: `Write clean, working code with comments: ${request}`,
                payment: '0.008',
                temperature: 0.2,
                maxTokens: 1500
            });
            
            const result = await this.sdk.jobs.waitForResult(job.id, 45000);
            
            // Format code response
            const codeBlocks = this.extractCodeBlocks(result.data);
            
            if (codeBlocks.length > 0) {
                for (const block of codeBlocks) {
                    await message.channel.send(`\`\`\`${block.language}\n${block.code}\n\`\`\``);
                }
            } else {
                await reply.edit(result.data);
            }
            
        } catch (error) {
            message.reply('Failed to generate code.');
        }
    }
    
    async handleSummarize(message, args) {
        try {
            // Check if replying to a message
            if (!message.reference) {
                return message.reply('Reply to a message to summarize it!');
            }
            
            const targetMessage = await message.channel.messages.fetch(
                message.reference.messageId
            );
            
            if (!targetMessage.content) {
                return message.reply('No text content to summarize.');
            }
            
            const reply = await message.reply('📝 Summarizing...');
            
            const job = await this.sdk.jobs.create({
                modelId: 'gpt-3.5-turbo',
                prompt: `Summarize this concisely: ${targetMessage.content}`,
                payment: '0.003',
                maxTokens: 200
            });
            
            const result = await this.sdk.jobs.waitForResult(job.id);
            
            await reply.edit(`**Summary:**\n${result.data}`);
            
        } catch (error) {
            message.reply('Failed to summarize.');
        }
    }
    
    // Slash command handler
    async handleSlashCommand(interaction) {
        const { commandName, options } = interaction;
        
        switch (commandName) {
            case 'ask':
                await this.handleSlashAsk(interaction, options);
                break;
            case 'imagine':
                await this.handleSlashImage(interaction, options);
                break;
            case 'settings':
                await this.handleSettings(interaction, options);
                break;
        }
    }
    
    async handleSlashAsk(interaction, options) {
        const prompt = options.getString('prompt');
        const model = options.getString('model') || 'gpt-4';
        const private = options.getBoolean('private') || false;
        
        await interaction.deferReply({ ephemeral: private });
        
        try {
            const job = await this.sdk.jobs.create({
                modelId: model,
                prompt: prompt,
                payment: this.getModelPrice(model)
            });
            
            const result = await this.sdk.jobs.waitForResult(job.id);
            
            await interaction.editReply({
                embeds: [{
                    title: 'AI Response',
                    description: result.data,
                    color: 0x00ff00,
                    footer: {
                        text: `Model: ${model} | Cost: ${this.getModelPrice(model)} ETH`
                    }
                }]
            });
            
        } catch (error) {
            await interaction.editReply('Failed to generate response.');
        }
    }
    
    // Helper methods
    buildPrompt(type, userPrompt, message) {
        const context = {
            username: message.author.username,
            channel: message.channel.name,
            server: message.guild.name
        };
        
        const templates = {
            question: `Answer this question helpfully and concisely: ${userPrompt}`,
            mention: `Respond naturally to this message: ${userPrompt}`,
            conversation: `Continue this conversation naturally: ${userPrompt}`
        };
        
        return templates[type] || userPrompt;
    }
    
    async checkRateLimit(userId) {
        const key = `ratelimit:${userId}`;
        const current = await this.redis.get(key);
        
        if (current && parseInt(current) >= 10) {
            return false;
        }
        
        await this.redis.incr(key);
        await this.redis.expire(key, 3600); // 1 hour
        
        return true;
    }
    
    async trackUserJob(userId, jobId) {
        const key = `user:${userId}:jobs`;
        await this.redis.lpush(key, jobId);
        await this.redis.ltrim(key, 0, 99); // Keep last 100
    }
    
    formatResponse(text) {
        // Split long responses
        if (text.length > 2000) {
            return text.substring(0, 1997) + '...';
        }
        return text;
    }
    
    extractCodeBlocks(text) {
        const regex = /```(\w+)?\n([\s\S]*?)```/g;
        const blocks = [];
        let match;
        
        while ((match = regex.exec(text)) !== null) {
            blocks.push({
                language: match[1] || 'plaintext',
                code: match[2].trim()
            });
        }
        
        return blocks;
    }
    
    getModelPrice(model) {
        const prices = {
            'gpt-4': '0.01',
            'gpt-3.5-turbo': '0.002',
            'claude-2': '0.008',
            'llama-2-70b': '0.005'
        };
        return prices[model] || '0.005';
    }
    
    async start() {
        await this.redis.connect();
        await this.registerSlashCommands();
        await this.client.login(process.env.DISCORD_TOKEN);
    }
}

// Start bot
const bot = new FabstirBot();
bot.start();
```

## Best Practices

### 1. Architecture Considerations

```javascript
// Modular architecture
class FabstirApplication {
    constructor() {
        this.modules = new Map();
        this.initializeCore();
    }
    
    initializeCore() {
        // Core modules
        this.registerModule('auth', new AuthModule());
        this.registerModule('jobs', new JobModule());
        this.registerModule('payments', new PaymentModule());
        this.registerModule('analytics', new AnalyticsModule());
    }
    
    registerModule(name, module) {
        module.initialize(this);
        this.modules.set(name, module);
    }
    
    // Dependency injection
    getModule(name) {
        return this.modules.get(name);
    }
}

// Example module
class JobModule {
    initialize(app) {
        this.app = app;
        this.sdk = app.sdk;
        this.queue = new JobQueue();
    }
    
    async createJob(params) {
        // Validate
        const validation = await this.validateJobParams(params);
        if (!validation.valid) {
            throw new ValidationError(validation.errors);
        }
        
        // Check quotas
        const auth = this.app.getModule('auth');
        const user = await auth.getCurrentUser();
        await this.checkUserQuota(user);
        
        // Create job
        const job = await this.sdk.jobs.create(params);
        
        // Track
        const analytics = this.app.getModule('analytics');
        await analytics.track('job.created', {
            userId: user.id,
            jobId: job.id,
            model: params.modelId
        });
        
        return job;
    }
}
```

### 2. Error Handling & Recovery

```javascript
class ResilientJobProcessor {
    constructor(sdk) {
        this.sdk = sdk;
        this.retryPolicy = {
            maxAttempts: 3,
            backoff: 'exponential',
            initialDelay: 1000
        };
    }
    
    async processJobWithRetry(jobConfig) {
        let lastError;
        
        for (let attempt = 1; attempt <= this.retryPolicy.maxAttempts; attempt++) {
            try {
                return await this.processJob(jobConfig);
            } catch (error) {
                lastError = error;
                
                // Don't retry certain errors
                if (this.isNonRetryable(error)) {
                    throw error;
                }
                
                // Calculate delay
                const delay = this.calculateDelay(attempt);
                console.log(`Retry attempt ${attempt} after ${delay}ms`);
                
                await new Promise(resolve => setTimeout(resolve, delay));
            }
        }
        
        throw new Error(`Failed after ${this.retryPolicy.maxAttempts} attempts: ${lastError.message}`);
    }
    
    isNonRetryable(error) {
        const nonRetryableErrors = [
            'INSUFFICIENT_FUNDS',
            'INVALID_MODEL',
            'QUOTA_EXCEEDED'
        ];
        
        return nonRetryableErrors.includes(error.code);
    }
    
    calculateDelay(attempt) {
        if (this.retryPolicy.backoff === 'exponential') {
            return this.retryPolicy.initialDelay * Math.pow(2, attempt - 1);
        }
        return this.retryPolicy.initialDelay;
    }
}
```

### 3. Monitoring & Analytics

```javascript
class ApplicationMonitor {
    constructor() {
        this.metrics = {
            jobsCreated: 0,
            jobsCompleted: 0,
            jobsFailed: 0,
            totalCost: 0,
            avgResponseTime: 0
        };
    }
    
    trackJob(job) {
        this.metrics.jobsCreated++;
        
        // Track completion
        job.on('completed', (result) => {
            this.metrics.jobsCompleted++;
            this.metrics.totalCost += parseFloat(job.payment);
            this.updateAvgResponseTime(result.processingTime);
        });
        
        job.on('failed', () => {
            this.metrics.jobsFailed++;
        });
    }
    
    getHealthStatus() {
        const successRate = this.metrics.jobsCompleted / 
                          (this.metrics.jobsCompleted + this.metrics.jobsFailed);
        
        return {
            status: successRate > 0.95 ? 'healthy' : 'degraded',
            metrics: this.metrics,
            successRate: successRate
        };
    }
    
    exportMetrics() {
        // Prometheus format
        return `
# HELP fabstir_jobs_total Total number of jobs
# TYPE fabstir_jobs_total counter
fabstir_jobs_total{status="created"} ${this.metrics.jobsCreated}
fabstir_jobs_total{status="completed"} ${this.metrics.jobsCompleted}
fabstir_jobs_total{status="failed"} ${this.metrics.jobsFailed}

# HELP fabstir_cost_total Total cost in ETH
# TYPE fabstir_cost_total gauge
fabstir_cost_total ${this.metrics.totalCost}

# HELP fabstir_response_time_avg Average response time in ms
# TYPE fabstir_response_time_avg gauge
fabstir_response_time_avg ${this.metrics.avgResponseTime}
        `;
    }
}
```

## Deployment Considerations

### Container Deployment
```dockerfile
# Dockerfile
FROM node:18-alpine

WORKDIR /app

# Install dependencies
COPY package*.json ./
RUN npm ci --only=production

# Copy application
COPY . .

# Build TypeScript
RUN npm run build

# Create non-root user
RUN addgroup -g 1001 -S nodejs
RUN adduser -S nodejs -u 1001
USER nodejs

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s \
  CMD node healthcheck.js

EXPOSE 3000

CMD ["node", "dist/index.js"]
```

### Kubernetes Deployment
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fabstir-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: fabstir-app
  template:
    metadata:
      labels:
        app: fabstir-app
    spec:
      containers:
      - name: app
        image: your-registry/fabstir-app:latest
        ports:
        - containerPort: 3000
        env:
        - name: FABSTIR_NETWORK
          value: "mainnet"
        - name: FABSTIR_PRIVATE_KEY
          valueFrom:
            secretKeyRef:
              name: fabstir-secrets
              key: private-key
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
```

## Security Best Practices

### 1. API Key Management
```javascript
class SecureAPIKeyManager {
    constructor() {
        this.keys = new Map();
        this.rateLimiter = new RateLimiter();
    }
    
    async generateAPIKey(userId, permissions) {
        const key = this.generateSecureKey();
        const hashedKey = await this.hashKey(key);
        
        await this.storeKey(hashedKey, {
            userId,
            permissions,
            createdAt: Date.now(),
            lastUsed: null
        });
        
        // Return unhashed key only once
        return key;
    }
    
    generateSecureKey() {
        return `sk_${crypto.randomBytes(32).toString('hex')}`;
    }
    
    async validateKey(key) {
        const hashedKey = await this.hashKey(key);
        const keyData = await this.getKeyData(hashedKey);
        
        if (!keyData) {
            return { valid: false };
        }
        
        // Check rate limits
        if (!this.rateLimiter.check(hashedKey)) {
            return { valid: false, error: 'Rate limit exceeded' };
        }
        
        // Update last used
        await this.updateLastUsed(hashedKey);
        
        return {
            valid: true,
            userId: keyData.userId,
            permissions: keyData.permissions
        };
    }
}
```

### 2. Input Validation
```javascript
class InputValidator {
    static validateJobRequest(request) {
        const errors = [];
        
        // Model validation
        if (!ALLOWED_MODELS.includes(request.model)) {
            errors.push('Invalid model');
        }
        
        // Prompt validation
        if (!request.prompt || request.prompt.length > MAX_PROMPT_LENGTH) {
            errors.push('Invalid prompt length');
        }
        
        // Sanitize prompt
        request.prompt = this.sanitizePrompt(request.prompt);
        
        // Parameter validation
        if (request.temperature && (request.temperature < 0 || request.temperature > 2)) {
            errors.push('Temperature must be between 0 and 2');
        }
        
        return {
            valid: errors.length === 0,
            errors,
            sanitized: request
        };
    }
    
    static sanitizePrompt(prompt) {
        // Remove potential injection attempts
        return prompt
            .replace(/[<>]/g, '') // Remove HTML tags
            .replace(/\\x[0-9a-fA-F]{2}/g, '') // Remove hex escapes
            .trim();
    }
}
```

## Performance Optimization

### Caching Strategy
```javascript
class SmartCache {
    constructor() {
        this.cache = new LRUCache({
            max: 1000,
            ttl: 1000 * 60 * 60, // 1 hour
            updateAgeOnGet: true
        });
        
        this.stats = {
            hits: 0,
            misses: 0
        };
    }
    
    async get(key, generator) {
        const cached = this.cache.get(key);
        
        if (cached) {
            this.stats.hits++;
            return cached;
        }
        
        this.stats.misses++;
        
        // Generate and cache
        const value = await generator();
        this.cache.set(key, value);
        
        return value;
    }
    
    getCacheKey(model, prompt, params) {
        // Create deterministic cache key
        const normalized = {
            model,
            prompt: prompt.toLowerCase().trim(),
            params: this.normalizeParams(params)
        };
        
        return crypto
            .createHash('sha256')
            .update(JSON.stringify(normalized))
            .digest('hex');
    }
    
    getHitRate() {
        const total = this.stats.hits + this.stats.misses;
        return total > 0 ? this.stats.hits / total : 0;
    }
}
```

## Next Steps

1. **[Advanced Monitoring](../advanced/monitoring-setup.md)** - Monitor your application
2. **[Governance Integration](../advanced/governance-participation.md)** - Participate in governance
3. **[SDK Reference](sdk-usage.md)** - Detailed SDK documentation

## Resources

- [Example Applications](https://github.com/fabstir/example-apps)
- [Architecture Patterns](https://fabstir.com/patterns)
- [Security Guidelines](https://fabstir.com/security)
- [Performance Tuning](https://fabstir.com/performance)

---

Ready to build? Join our [Builders Program](https://fabstir.com/builders) →