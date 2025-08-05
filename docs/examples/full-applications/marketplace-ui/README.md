# Fabstir Marketplace UI

A modern web interface for the Fabstir P2P LLM marketplace, allowing users to browse nodes, post jobs, and monitor the network.

## Overview

This marketplace UI provides:
- 🏠 Dashboard with network statistics
- 🖥️ Node registry browsing and filtering
- 💼 Job marketplace with posting and monitoring
- 📊 Analytics and performance metrics
- 👛 Wallet integration and balance management
- 🔔 Real-time notifications

## Features

### For Job Posters
- Browse available nodes by model and performance
- Post AI inference jobs with custom parameters
- Monitor job progress in real-time
- View cost estimates before posting
- Access job history and results

### For Node Operators
- Register and manage nodes
- View earnings and performance metrics
- Monitor reputation score
- Claim and complete jobs
- Withdraw earnings

### For Everyone
- Network statistics and health monitoring
- Model availability tracking
- Price discovery and trends
- Leaderboards and rankings

## Tech Stack

- **Frontend**: React 18 with TypeScript
- **Styling**: Tailwind CSS
- **State Management**: Zustand
- **Web3**: ethers.js v5
- **Charts**: Chart.js
- **Routing**: React Router v6
- **Build Tool**: Vite

## Installation

```bash
# Clone the repository
cd marketplace-ui

# Install dependencies
npm install

# Copy environment file
cp .env.example .env

# Start development server
npm run dev
```

## Project Structure

```
marketplace-ui/
├── README.md
├── src/
│   ├── components/       # Reusable UI components
│   │   ├── Layout/
│   │   ├── Dashboard/
│   │   ├── NodeList/
│   │   ├── JobBoard/
│   │   └── WalletConnect/
│   ├── pages/           # Page components
│   │   ├── Home.tsx
│   │   ├── Nodes.tsx
│   │   ├── Jobs.tsx
│   │   ├── Analytics.tsx
│   │   └── Profile.tsx
│   ├── services/        # API and Web3 services
│   │   ├── contracts.ts
│   │   ├── api.ts
│   │   └── websocket.ts
│   ├── store/          # State management
│   │   ├── wallet.ts
│   │   ├── jobs.ts
│   │   └── nodes.ts
│   ├── utils/          # Utility functions
│   ├── types/          # TypeScript types
│   └── App.tsx         # Main app component
├── public/             # Static assets
├── package.json
└── vite.config.ts
```

## Key Components

### Dashboard
Shows network overview with:
- Total nodes and jobs
- Network volume and fees
- Active models
- Recent activity feed

### Node Registry
Browse and filter nodes by:
- Supported models
- Reputation score
- Success rate
- Geographic region
- Pricing

### Job Marketplace
Post and manage jobs:
- Model selection
- Token limits
- Deadline setting
- Cost estimation
- Progress tracking

### Wallet Integration
Seamless Web3 experience:
- MetaMask support
- WalletConnect
- Balance display
- Transaction history
- Gas estimation

## Configuration

### Environment Variables
```env
# API endpoints
VITE_API_URL=http://localhost:3001
VITE_WS_URL=ws://localhost:3002

# Contract addresses (Base mainnet)
VITE_NODE_REGISTRY=0x...
VITE_JOB_MARKETPLACE=0x...
VITE_PAYMENT_ESCROW=0x...
VITE_REPUTATION_SYSTEM=0x...

# Network config
VITE_CHAIN_ID=8453
VITE_RPC_URL=https://base-mainnet.g.alchemy.com/v2/YOUR_KEY

# Features
VITE_ENABLE_TESTNET=false
VITE_ENABLE_ANALYTICS=true
```

## Usage Guide

### Posting a Job

1. Connect your wallet
2. Navigate to "Post Job"
3. Select AI model
4. Enter your prompt
5. Set max tokens and deadline
6. Review cost estimate
7. Confirm transaction

### Registering as a Node

1. Connect wallet with 100+ ETH
2. Go to "Become a Node"
3. Select supported models
4. Choose regions
5. Stake required ETH
6. Confirm registration

### Monitoring Jobs

1. Go to "My Jobs"
2. View active/completed jobs
3. Click job for details
4. Download results
5. Rate node performance

## Development

### Running Tests
```bash
npm run test
npm run test:coverage
```

### Building for Production
```bash
npm run build
npm run preview
```

### Code Style
```bash
npm run lint
npm run format
```

## API Integration

The UI communicates with the backend API for:
- Job management
- Node information
- Network statistics
- Price data
- User profiles

See `src/services/api.ts` for implementation.

## Smart Contract Integration

Direct contract calls for:
- Job posting
- Node registration
- Balance queries
- Event monitoring

See `src/services/contracts.ts` for implementation.

## Responsive Design

The UI is fully responsive with breakpoints:
- Mobile: < 640px
- Tablet: 640px - 1024px
- Desktop: > 1024px

## Performance Optimizations

- Lazy loading of routes
- Image optimization
- Bundle splitting
- Service worker caching
- WebSocket connection pooling

## Security Considerations

- No private key storage
- Transaction simulation before execution
- Input validation
- XSS protection
- CORS configuration

## Deployment

### Vercel
```bash
npm run build
vercel --prod
```

### Netlify
```bash
npm run build
netlify deploy --prod --dir=dist
```

### Docker
```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build
EXPOSE 3000
CMD ["npm", "run", "preview"]
```

## Contributing

1. Fork the repository
2. Create feature branch
3. Make changes
4. Run tests
5. Submit pull request

## License

MIT