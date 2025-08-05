# AI Chatbot Application

A complete AI chatbot application that uses the Fabstir network for decentralized AI inference.

## Overview

This example demonstrates a full-stack chatbot application with:
- React frontend with chat interface
- Node.js backend API server
- Integration with Fabstir smart contracts
- Real-time message streaming
- Multi-model support

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌──────────────┐
│   Frontend  │────▶│   Backend   │────▶│   Fabstir    │
│   (React)   │     │  (Node.js)  │     │  Contracts   │
└─────────────┘     └─────────────┘     └──────────────┘
                           │                      │
                           └──────────────────────┘
                              WebSocket for
                             status updates
```

## Features

- 🤖 Multiple AI model support (GPT-4, Claude-2, Llama-2)
- 💬 Real-time chat interface
- 📊 Usage tracking and billing
- 🔒 Secure wallet integration
- 📈 Performance metrics
- 🎨 Modern, responsive UI

## Prerequisites

- Node.js v18+
- npm or yarn
- MetaMask or compatible wallet
- Base network ETH for transactions

## Installation

```bash
# Clone the repository
git clone [repository-url]
cd ai-chatbot

# Install dependencies
npm install

# Set up environment variables
cp .env.example .env
# Edit .env with your values

# Start the application
npm run dev
```

## Configuration

Edit `.env` file:
```bash
# Backend configuration
PORT=3001
RPC_URL=https://base-mainnet.g.alchemy.com/v2/YOUR_KEY
PRIVATE_KEY=your-private-key-for-job-posting

# Contract addresses
NODE_REGISTRY=0x...
JOB_MARKETPLACE=0x...
PAYMENT_ESCROW=0x...

# Frontend configuration
REACT_APP_API_URL=http://localhost:3001
REACT_APP_WS_URL=ws://localhost:3001
```

## Usage

1. **Start the backend:**
   ```bash
   cd backend
   npm start
   ```

2. **Start the frontend:**
   ```bash
   cd frontend
   npm start
   ```

3. **Connect wallet** in the UI

4. **Select AI model** from dropdown

5. **Start chatting!**

## Project Structure

```
ai-chatbot/
├── README.md
├── backend.js         # Express API server
├── frontend.html      # Single-page React app
├── package.json       # Dependencies
├── .env.example       # Environment template
└── public/           # Static assets
    ├── styles.css
    └── logo.png
```

## API Endpoints

### POST /api/chat
Send a message to the AI
```json
{
  "message": "Hello, AI!",
  "model": "gpt-4",
  "maxTokens": 1000
}
```

### GET /api/models
Get available AI models
```json
[
  {
    "id": "gpt-4",
    "name": "GPT-4",
    "costPerToken": "0.00003"
  }
]
```

### GET /api/history
Get chat history for the connected wallet

### GET /api/balance
Get escrow balance for the connected wallet

## WebSocket Events

- `job-posted`: Job submitted to marketplace
- `job-claimed`: Node claimed the job
- `job-completed`: Response ready
- `job-failed`: Processing failed
- `status-update`: General status updates

## Cost Estimation

The app automatically estimates costs based on:
- Selected model pricing
- Estimated token usage
- Current gas prices
- Network congestion

## Security Considerations

- Private keys are never sent to the frontend
- All contract interactions are server-side
- Rate limiting on API endpoints
- Input validation and sanitization
- CORS properly configured

## Troubleshooting

### "Insufficient funds"
- Ensure wallet has enough ETH
- Check escrow balance

### "No nodes available"
- Selected model may not have active nodes
- Try a different model

### WebSocket disconnections
- Check network connectivity
- Verify backend is running

## Deployment

### Backend (Heroku example)
```bash
heroku create your-chatbot-api
heroku config:set RPC_URL=...
heroku config:set PRIVATE_KEY=...
git push heroku main
```

### Frontend (Vercel example)
```bash
vercel --prod
```

## Contributing

Feel free to submit issues and enhancement requests!

## License

MIT