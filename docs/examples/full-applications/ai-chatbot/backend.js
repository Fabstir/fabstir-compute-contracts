/**
 * AI Chatbot Backend
 * Handles Fabstir contract interactions and serves API for frontend
 */

const express = require('express');
const cors = require('cors');
const WebSocket = require('ws');
const { ethers } = require('ethers');
const multer = require('multer');
require('dotenv').config();

// Contract ABIs
const JOB_MARKETPLACE_ABI = [
    'function postJob(string modelId, uint256 maxTokens, uint256 deadline, bytes inputData) payable returns (uint256)',
    'function getJob(uint256 jobId) view returns (tuple(uint256 id, address poster, string modelId, uint256 payment, uint256 maxTokens, uint256 deadline, address assignedHost, uint8 status, bytes inputData, bytes outputData, uint256 postedAt, uint256 completedAt))',
    'function MIN_JOB_PAYMENT() view returns (uint256)',
    'event JobPosted(uint256 indexed jobId, address indexed poster, string modelId, uint256 payment)',
    'event JobCompleted(uint256 indexed jobId, address indexed host, uint256 payment)'
];

const PAYMENT_ESCROW_ABI = [
    'function deposit(address token, uint256 amount) payable',
    'function getBalance(address account, address token) view returns (uint256)'
];

// Configuration
const config = {
    port: process.env.PORT || 3001,
    rpcUrl: process.env.RPC_URL,
    privateKey: process.env.PRIVATE_KEY,
    contracts: {
        jobMarketplace: process.env.JOB_MARKETPLACE,
        paymentEscrow: process.env.PAYMENT_ESCROW
    },
    models: [
        { id: 'gpt-4', name: 'GPT-4', costPerToken: 0.00003, maxTokens: 8192 },
        { id: 'claude-2', name: 'Claude 2', costPerToken: 0.00002, maxTokens: 100000 },
        { id: 'llama-2-70b', name: 'Llama 2 70B', costPerToken: 0.00001, maxTokens: 4096 },
        { id: 'mistral-7b', name: 'Mistral 7B', costPerToken: 0.000005, maxTokens: 8192 }
    ],
    defaultDeadline: 3600, // 1 hour
    maxHistoryLength: 100
};

// Initialize Express app
const app = express();
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// Initialize providers and contracts
const provider = new ethers.JsonRpcProvider(config.rpcUrl);
const wallet = new ethers.Wallet(config.privateKey, provider);
const jobMarketplace = new ethers.Contract(config.contracts.jobMarketplace, JOB_MARKETPLACE_ABI, wallet);
const paymentEscrow = new ethers.Contract(config.contracts.paymentEscrow, PAYMENT_ESCROW_ABI, wallet);

// WebSocket server for real-time updates
const wss = new WebSocket.Server({ port: 3002 });
const clients = new Map(); // userId -> WebSocket

// In-memory storage (use database in production)
const chatHistory = new Map(); // userId -> messages[]
const activeJobs = new Map(); // jobId -> job details

// WebSocket connection handler
wss.on('connection', (ws, req) => {
    const userId = req.url.slice(1); // Extract userId from URL
    clients.set(userId, ws);
    
    console.log(`Client connected: ${userId}`);
    
    ws.on('close', () => {
        clients.delete(userId);
        console.log(`Client disconnected: ${userId}`);
    });
    
    ws.on('error', (error) => {
        console.error(`WebSocket error for ${userId}:`, error);
    });
});

// Broadcast updates to specific user
function broadcastToUser(userId, message) {
    const client = clients.get(userId);
    if (client && client.readyState === WebSocket.OPEN) {
        client.send(JSON.stringify(message));
    }
}

// API Routes

// Get available models
app.get('/api/models', (req, res) => {
    res.json(config.models);
});

// Get chat history
app.get('/api/history/:userId', (req, res) => {
    const history = chatHistory.get(req.params.userId) || [];
    res.json(history.slice(-config.maxHistoryLength));
});

// Get user's escrow balance
app.get('/api/balance/:address', async (req, res) => {
    try {
        const balance = await paymentEscrow.getBalance(req.params.address, ethers.ZeroAddress);
        res.json({ balance: ethers.formatEther(balance) });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Post a new chat message
app.post('/api/chat', async (req, res) => {
    try {
        const { userId, message, model, maxTokens = 1000, userAddress } = req.body;
        
        // Validate inputs
        if (!userId || !message || !model) {
            return res.status(400).json({ error: 'Missing required fields' });
        }
        
        const modelConfig = config.models.find(m => m.id === model);
        if (!modelConfig) {
            return res.status(400).json({ error: 'Invalid model' });
        }
        
        // Store user message
        if (!chatHistory.has(userId)) {
            chatHistory.set(userId, []);
        }
        const history = chatHistory.get(userId);
        
        const userMessage = {
            id: Date.now(),
            role: 'user',
            content: message,
            timestamp: new Date().toISOString()
        };
        history.push(userMessage);
        
        // Calculate payment
        const estimatedTokens = Math.min(message.length + 500, maxTokens); // Rough estimate
        const costInEth = modelConfig.costPerToken * estimatedTokens;
        const payment = ethers.parseEther(costInEth.toFixed(6));
        
        // Check minimum payment
        const minPayment = await jobMarketplace.MIN_JOB_PAYMENT();
        const finalPayment = payment > minPayment ? payment : minPayment;
        
        // Encode job input
        const inputData = ethers.AbiCoder.defaultAbiCoder().encode(
            ['string', 'uint256', 'string', 'string[]'],
            [message, maxTokens, 'chatbot-v1', history.slice(-5).map(m => m.content)]
        );
        
        // Post job to marketplace
        console.log(`Posting job for ${userId}: ${model}, ${ethers.formatEther(finalPayment)} ETH`);
        
        const tx = await jobMarketplace.postJob(
            model,
            maxTokens,
            config.defaultDeadline,
            inputData,
            { value: finalPayment }
        );
        
        const receipt = await tx.wait();
        
        // Extract job ID from event
        const event = receipt.logs
            .map(log => {
                try {
                    return jobMarketplace.interface.parseLog(log);
                } catch {
                    return null;
                }
            })
            .find(e => e && e.name === 'JobPosted');
        
        if (!event) {
            throw new Error('Job posting failed - no event found');
        }
        
        const jobId = event.args[0].toString();
        
        // Store job details
        activeJobs.set(jobId, {
            userId,
            messageId: userMessage.id,
            model,
            payment: finalPayment,
            status: 'posted',
            postedAt: Date.now()
        });
        
        // Send response
        res.json({
            success: true,
            jobId,
            messageId: userMessage.id,
            estimatedCost: ethers.formatEther(finalPayment)
        });
        
        // Notify user via WebSocket
        broadcastToUser(userId, {
            type: 'job-posted',
            jobId,
            messageId: userMessage.id,
            model,
            cost: ethers.formatEther(finalPayment)
        });
        
        // Start monitoring the job
        monitorJob(jobId);
        
    } catch (error) {
        console.error('Chat error:', error);
        res.status(500).json({ error: error.message });
    }
});

// Monitor job status
async function monitorJob(jobId) {
    const checkInterval = setInterval(async () => {
        try {
            const job = await jobMarketplace.getJob(jobId);
            const jobDetails = activeJobs.get(jobId);
            
            if (!jobDetails) {
                clearInterval(checkInterval);
                return;
            }
            
            const status = ['posted', 'claimed', 'completed', 'cancelled'][job.status];
            
            // Update status if changed
            if (status !== jobDetails.status) {
                jobDetails.status = status;
                
                broadcastToUser(jobDetails.userId, {
                    type: `job-${status}`,
                    jobId,
                    messageId: jobDetails.messageId
                });
                
                if (status === 'claimed') {
                    console.log(`Job ${jobId} claimed by ${job.assignedHost}`);
                }
                
                if (status === 'completed') {
                    // Decode output
                    const [output] = ethers.AbiCoder.defaultAbiCoder().decode(
                        ['string', 'uint256', 'uint256', 'string'],
                        job.outputData
                    );
                    
                    // Store AI response
                    const history = chatHistory.get(jobDetails.userId);
                    const aiMessage = {
                        id: Date.now(),
                        role: 'assistant',
                        content: output,
                        timestamp: new Date().toISOString(),
                        model: jobDetails.model,
                        jobId
                    };
                    history.push(aiMessage);
                    
                    // Send completion notification
                    broadcastToUser(jobDetails.userId, {
                        type: 'job-completed',
                        jobId,
                        messageId: jobDetails.messageId,
                        response: output
                    });
                    
                    console.log(`Job ${jobId} completed successfully`);
                    clearInterval(checkInterval);
                    activeJobs.delete(jobId);
                }
                
                if (status === 'cancelled') {
                    console.log(`Job ${jobId} cancelled`);
                    clearInterval(checkInterval);
                    activeJobs.delete(jobId);
                }
            }
            
            // Timeout after 2 hours
            if (Date.now() - jobDetails.postedAt > 2 * 60 * 60 * 1000) {
                console.log(`Job ${jobId} timed out`);
                broadcastToUser(jobDetails.userId, {
                    type: 'job-timeout',
                    jobId,
                    messageId: jobDetails.messageId
                });
                clearInterval(checkInterval);
                activeJobs.delete(jobId);
            }
            
        } catch (error) {
            console.error(`Error monitoring job ${jobId}:`, error);
        }
    }, 5000); // Check every 5 seconds
}

// Estimate cost endpoint
app.post('/api/estimate', async (req, res) => {
    try {
        const { message, model, maxTokens = 1000 } = req.body;
        
        const modelConfig = config.models.find(m => m.id === model);
        if (!modelConfig) {
            return res.status(400).json({ error: 'Invalid model' });
        }
        
        // Estimate tokens (rough approximation)
        const estimatedTokens = Math.min(
            message.length + 500, // Input + expected output
            Math.min(maxTokens, modelConfig.maxTokens)
        );
        
        const costInEth = modelConfig.costPerToken * estimatedTokens;
        const minPayment = await jobMarketplace.MIN_JOB_PAYMENT();
        const payment = ethers.parseEther(costInEth.toFixed(6));
        const finalPayment = payment > minPayment ? payment : minPayment;
        
        // Get current gas price
        const feeData = await provider.getFeeData();
        const gasEstimate = 300000n; // Rough estimate
        const gasCost = gasEstimate * feeData.gasPrice;
        
        res.json({
            estimatedTokens,
            jobCost: ethers.formatEther(finalPayment),
            gasCost: ethers.formatEther(gasCost),
            totalCost: ethers.formatEther(finalPayment + gasCost),
            breakdown: {
                costPerToken: modelConfig.costPerToken,
                tokens: estimatedTokens,
                gasPrice: ethers.formatUnits(feeData.gasPrice, 'gwei') + ' gwei'
            }
        });
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Get active jobs for user
app.get('/api/jobs/:userId', (req, res) => {
    const userJobs = [];
    
    for (const [jobId, details] of activeJobs) {
        if (details.userId === req.params.userId) {
            userJobs.push({
                jobId,
                ...details,
                payment: ethers.formatEther(details.payment)
            });
        }
    }
    
    res.json(userJobs);
});

// Health check
app.get('/health', async (req, res) => {
    try {
        const blockNumber = await provider.getBlockNumber();
        res.json({
            status: 'healthy',
            blockNumber,
            activeJobs: activeJobs.size,
            connectedClients: clients.size
        });
    } catch (error) {
        res.status(500).json({
            status: 'unhealthy',
            error: error.message
        });
    }
});

// Error handling middleware
app.use((err, req, res, next) => {
    console.error(err.stack);
    res.status(500).json({ error: 'Internal server error' });
});

// Start server
const server = app.listen(config.port, () => {
    console.log(`🚀 AI Chatbot Backend running on port ${config.port}`);
    console.log(`📡 WebSocket server on port 3002`);
    console.log(`🔗 RPC: ${config.rpcUrl}`);
    console.log(`📍 Marketplace: ${config.contracts.jobMarketplace}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('SIGTERM received, shutting down gracefully...');
    server.close(() => {
        console.log('HTTP server closed');
        wss.close(() => {
            console.log('WebSocket server closed');
            process.exit(0);
        });
    });
});

// Contract event listeners (optional - for additional monitoring)
jobMarketplace.on('JobCompleted', async (jobId, host, payment) => {
    const jobDetails = activeJobs.get(jobId.toString());
    if (jobDetails) {
        console.log(`Job ${jobId} completed by ${host}, payment: ${ethers.formatEther(payment)} ETH`);
    }
});

module.exports = app;