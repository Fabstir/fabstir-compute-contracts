# Fabstir API Gateway

A REST API gateway that provides easy access to Fabstir's decentralized AI network without requiring direct blockchain interaction.

## Overview

The API Gateway simplifies integration by:
- 🔐 Managing wallet operations server-side
- 🚀 Providing simple REST endpoints
- 💰 Handling payment and escrow automatically
- 📊 Aggregating network statistics
- 🔄 Managing job lifecycle
- 🛡️ Rate limiting and authentication

## Features

- **Simple Integration**: REST API with API keys
- **Multi-tenant**: Support multiple applications/users
- **Auto-scaling**: Handle high request volumes
- **Caching**: Reduce blockchain calls
- **Webhooks**: Real-time job updates
- **Analytics**: Usage tracking and billing

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌──────────────┐
│   Client    │────▶│ API Gateway │────▶│   Fabstir    │
│   (REST)    │     │  (Node.js)  │     │  Contracts   │
└─────────────┘     └─────────────┘     └──────────────┘
                           │
                           ├── Redis (Cache)
                           ├── PostgreSQL (State)
                           └── Queue (Jobs)
```

## Quick Start

```bash
# Clone and install
cd api-gateway
npm install

# Configure environment
cp .env.example .env
# Edit .env with your values

# Run migrations
npm run migrate

# Start server
npm start
```

## API Endpoints

### Authentication

#### POST /api/auth/register
Register new API user
```json
{
  "email": "user@example.com",
  "organization": "ACME Corp"
}
```

#### POST /api/auth/login
Get API key
```json
{
  "email": "user@example.com",
  "password": "your-password"
}
```

### AI Inference

#### POST /api/v1/completions
Submit inference request
```bash
curl -X POST https://api.fabstir.network/v1/completions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4",
    "prompt": "Explain quantum computing",
    "max_tokens": 1000,
    "temperature": 0.7
  }'
```

Response:
```json
{
  "id": "job_123abc",
  "object": "text_completion",
  "created": 1677649420,
  "model": "gpt-4",
  "choices": [{
    "text": "Quantum computing is...",
    "index": 0,
    "finish_reason": "stop"
  }],
  "usage": {
    "prompt_tokens": 5,
    "completion_tokens": 127,
    "total_tokens": 132
  }
}
```

#### GET /api/v1/jobs/:id
Get job status
```json
{
  "id": "job_123abc",
  "status": "completed",
  "created_at": "2024-01-15T10:30:00Z",
  "completed_at": "2024-01-15T10:30:45Z",
  "cost": "0.0132",
  "result": {
    "text": "Quantum computing is...",
    "tokens_used": 132
  }
}
```

### Models

#### GET /api/v1/models
List available models
```json
{
  "object": "list",
  "data": [
    {
      "id": "gpt-4",
      "object": "model",
      "created": 1677649420,
      "owned_by": "openai",
      "permission": ["query"],
      "root": "gpt-4",
      "parent": null
    }
  ]
}
```

### Account Management

#### GET /api/v1/account
Get account info
```json
{
  "id": "user_123",
  "email": "user@example.com",
  "balance": "1.2345",
  "usage": {
    "current_month": "0.5678",
    "last_month": "0.9012"
  },
  "limits": {
    "rate_limit": 1000,
    "daily_spend": "10.0"
  }
}
```

#### POST /api/v1/account/deposit
Add funds to account
```json
{
  "amount": "1.0",
  "currency": "ETH"
}
```

### Webhooks

#### POST /api/v1/webhooks
Create webhook endpoint
```json
{
  "url": "https://your-app.com/webhook",
  "events": ["job.completed", "job.failed"],
  "secret": "whsec_..."
}
```

## WebSocket Support

Connect for real-time updates:
```javascript
const ws = new WebSocket('wss://api.fabstir.network/v1/stream');

ws.on('message', (data) => {
  const event = JSON.parse(data);
  console.log('Event:', event.type, event.data);
});
```

## SDK Examples

### JavaScript/TypeScript
```javascript
import { FabstirClient } from '@fabstir/sdk';

const client = new FabstirClient({
  apiKey: 'YOUR_API_KEY'
});

const completion = await client.completions.create({
  model: 'gpt-4',
  prompt: 'Hello world',
  max_tokens: 100
});
```

### Python
```python
from fabstir import FabstirClient

client = FabstirClient(api_key="YOUR_API_KEY")

completion = client.completions.create(
    model="gpt-4",
    prompt="Hello world",
    max_tokens=100
)
```

### cURL
```bash
curl https://api.fabstir.network/v1/completions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d '{"model": "gpt-4", "prompt": "Hello", "max_tokens": 50}'
```

## Configuration

### Environment Variables
```env
# Server
PORT=3000
NODE_ENV=production

# Database
DATABASE_URL=postgresql://user:pass@localhost/fabstir
REDIS_URL=redis://localhost:6379

# Blockchain
RPC_URL=https://base-mainnet.g.alchemy.com/v2/KEY
PRIVATE_KEY=0x...
CHAIN_ID=8453

# Contracts
NODE_REGISTRY=0x...
JOB_MARKETPLACE=0x...
PAYMENT_ESCROW=0x...

# Security
JWT_SECRET=your-secret-key
ENCRYPTION_KEY=32-byte-key

# External services
SENDGRID_API_KEY=...
STRIPE_SECRET_KEY=...
```

## Rate Limiting

Default limits per tier:
- **Free**: 100 requests/day, 10 requests/minute
- **Basic**: 10,000 requests/day, 100 requests/minute
- **Pro**: 100,000 requests/day, 1000 requests/minute
- **Enterprise**: Custom limits

## Pricing

### Pay-as-you-go
- **API calls**: $0.001 per request
- **Compute**: Model-specific pricing
- **Storage**: $0.10 per GB/month
- **Bandwidth**: $0.05 per GB

### Subscription Plans
- **Free**: $0/month (100 requests)
- **Basic**: $49/month (10K requests)
- **Pro**: $299/month (100K requests)
- **Enterprise**: Custom pricing

## Security

### Authentication
- API key authentication
- JWT for session management
- OAuth2 support (optional)

### Encryption
- TLS 1.3 for all connections
- AES-256 for data at rest
- Request signing (optional)

### Best Practices
- Rotate API keys regularly
- Use webhook signatures
- Implement IP whitelisting
- Monitor for anomalies

## Deployment

### Docker
```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --production
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
```

### Kubernetes
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api-gateway
  template:
    metadata:
      labels:
        app: api-gateway
    spec:
      containers:
      - name: api-gateway
        image: fabstir/api-gateway:latest
        ports:
        - containerPort: 3000
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: api-secrets
              key: database-url
```

### Scaling
- Horizontal scaling with load balancer
- Redis for session sharing
- PostgreSQL with read replicas
- Queue workers for async jobs

## Monitoring

### Metrics
- Request rate and latency
- Error rates by endpoint
- Job completion times
- Blockchain gas usage
- User activity

### Logging
- Structured JSON logs
- Request/response logging
- Error tracking
- Audit trail

### Alerts
- High error rate
- Low balance warning
- Job failures
- Rate limit exceeded
- System health

## Migration Guide

### From OpenAI
```javascript
// Before (OpenAI)
const openai = new OpenAI({ apiKey: 'sk-...' });
const completion = await openai.completions.create({
  model: 'text-davinci-003',
  prompt: 'Hello'
});

// After (Fabstir)
const fabstir = new FabstirClient({ apiKey: 'fsk-...' });
const completion = await fabstir.completions.create({
  model: 'gpt-4',
  prompt: 'Hello'
});
```

## Troubleshooting

### Common Issues

#### "Insufficient balance"
- Check account balance
- Verify payment method
- Review spending limits

#### "Model not available"
- Check model status
- Try alternative model
- Contact support

#### "Rate limit exceeded"
- Upgrade plan
- Implement backoff
- Use batch requests

## Support

- Documentation: https://docs.fabstir.network
- Discord: https://discord.gg/fabstir
- Email: support@fabstir.network

## License

MIT