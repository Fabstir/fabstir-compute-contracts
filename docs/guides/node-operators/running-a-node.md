# Running a Fabstir Compute Node

This comprehensive guide covers everything you need to know about running a compute node on the Fabstir network.

## Prerequisites

- **Hardware Requirements**:
  - GPU: NVIDIA RTX 3090 or better (24GB+ VRAM recommended)
  - CPU: 16+ cores recommended
  - RAM: 64GB minimum, 128GB recommended
  - Storage: 1TB+ NVMe SSD
  - Network: 1Gbps+ connection

- **Software Requirements**:
  - Ubuntu 22.04 LTS or similar
  - NVIDIA drivers (535.x or newer)
  - Docker and NVIDIA Container Toolkit
  - Python 3.10+
  - Node.js 18+

- **Financial Requirements**:
  - 100 ETH for staking (on Base mainnet)
  - Additional ETH for gas fees
  - Hardware wallet recommended

## Architecture Overview

A Fabstir node consists of several components:

```
┌─────────────────────────────────────────┐
│           Fabstir Node Stack            │
├─────────────────────────────────────────┤
│      Job Manager (Node.js Service)      │
├─────────────────────────────────────────┤
│     Model Runner (Python + Docker)      │
├─────────────────────────────────────────┤
│      IPFS Node (Content Storage)        │
├─────────────────────────────────────────┤
│    Blockchain Client (Web3 Provider)    │
└─────────────────────────────────────────┘
```

## Step 1: System Preparation

### Update System and Install Dependencies
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install essential packages
sudo apt install -y \
    build-essential \
    curl \
    git \
    wget \
    software-properties-common \
    ca-certificates \
    gnupg \
    lsb-release

# Install Python 3.10
sudo add-apt-repository ppa:deadsnakes/ppa
sudo apt update
sudo apt install -y python3.10 python3.10-venv python3.10-dev

# Install Node.js 18
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs
```

### Install NVIDIA Drivers and CUDA
```bash
# Add NVIDIA repository
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.0-1_all.deb
sudo dpkg -i cuda-keyring_1.0-1_all.deb
sudo apt update

# Install CUDA and drivers
sudo apt install -y cuda-12-3

# Verify installation
nvidia-smi
```

### Install Docker with NVIDIA Support
```bash
# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Install NVIDIA Container Toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
sudo apt update
sudo apt install -y nvidia-docker2

# Restart Docker
sudo systemctl restart docker

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

## Step 2: Install Fabstir Node Software

### Clone Node Repository
```bash
# Create working directory
mkdir -p ~/fabstir-node
cd ~/fabstir-node

# Clone the node software (example repository)
git clone https://github.com/fabstir/fabstir-node.git
cd fabstir-node

# Install dependencies
npm install
```

### Configure Node
Create `config/node.json`:
```json
{
  "node": {
    "peerId": "will-be-generated",
    "region": "us-east-1",
    "operator": "0xYourWalletAddress"
  },
  "blockchain": {
    "network": "base-mainnet",
    "rpcUrl": "https://mainnet.base.org",
    "contracts": {
      "nodeRegistry": "0x...",
      "jobMarketplace": "0x...",
      "proofSystem": "0x..."
    }
  },
  "models": {
    "supported": [
      {
        "id": "gpt-4",
        "type": "llm",
        "provider": "openai-compatible",
        "endpoint": "http://localhost:8000/v1",
        "maxTokens": 8192,
        "requiresGPU": true,
        "minVRAM": 24
      },
      {
        "id": "llama-2-70b",
        "type": "llm",
        "provider": "vllm",
        "endpoint": "http://localhost:8001/v1",
        "maxTokens": 4096,
        "requiresGPU": true,
        "minVRAM": 80
      }
    ]
  },
  "ipfs": {
    "apiUrl": "http://localhost:5001",
    "gateway": "http://localhost:8080"
  },
  "monitoring": {
    "port": 9090,
    "enableMetrics": true
  }
}
```

### Set Up Environment Variables
Create `.env`:
```bash
# Node operator private key (NEVER share this!)
NODE_PRIVATE_KEY=0x...

# RPC endpoints
BASE_MAINNET_RPC=https://mainnet.base.org
BASE_MAINNET_WS=wss://mainnet.base.org

# Contract addresses
NODE_REGISTRY_ADDRESS=0x...
JOB_MARKETPLACE_ADDRESS=0x...
REPUTATION_SYSTEM_ADDRESS=0x...
PROOF_SYSTEM_ADDRESS=0x...

# Model API keys (if using commercial models)
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...

# Monitoring
GRAFANA_API_KEY=...
DISCORD_WEBHOOK=https://discord.com/api/webhooks/...
```

## Step 3: Set Up Model Runners

### Install vLLM for Open-Source Models
```bash
# Create Python virtual environment
python3.10 -m venv venv
source venv/bin/activate

# Install vLLM
pip install vllm

# Download model (example: Llama 2)
mkdir -p models
cd models

# Using Hugging Face CLI
pip install huggingface-hub
huggingface-cli download meta-llama/Llama-2-70b-chat-hf --local-dir ./llama-2-70b
```

### Create Model Service
Create `services/llama-service.py`:
```python
from vllm import LLM, SamplingParams
from vllm.entrypoints.api_server import app
import uvicorn

# Initialize model
llm = LLM(
    model="./models/llama-2-70b",
    tensor_parallel_size=2,  # Use 2 GPUs
    gpu_memory_utilization=0.95,
    max_model_len=4096
)

# API configuration
if __name__ == "__main__":
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8001,
        log_level="info"
    )
```

### Create Docker Compose Configuration
Create `docker-compose.yml`:
```yaml
version: '3.8'

services:
  ipfs:
    image: ipfs/go-ipfs:latest
    container_name: fabstir-ipfs
    ports:
      - "5001:5001"  # API
      - "8080:8080"  # Gateway
    volumes:
      - ./data/ipfs:/data/ipfs
    environment:
      - IPFS_PROFILE=server
    
  llama-service:
    build: ./services/llama
    container_name: fabstir-llama
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=0,1
    ports:
      - "8001:8001"
    volumes:
      - ./models:/models
      - ./cache:/root/.cache
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 2
              capabilities: [gpu]
  
  job-manager:
    build: .
    container_name: fabstir-job-manager
    depends_on:
      - ipfs
      - llama-service
    ports:
      - "3000:3000"  # API
      - "9090:9090"  # Metrics
    volumes:
      - ./config:/app/config
      - ./logs:/app/logs
    env_file:
      - .env
    restart: unless-stopped

  monitoring:
    image: prom/node-exporter:latest
    container_name: fabstir-metrics
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'
```

## Step 4: Register Your Node

### Generate Peer ID
```bash
# Run IPFS init to generate peer ID
docker-compose run --rm ipfs ipfs init

# Get peer ID
docker-compose run --rm ipfs ipfs config show | grep "PeerID"
```

### Register On-Chain
Create `scripts/register-node.js`:
```javascript
const { ethers } = require("ethers");
const config = require("../config/node.json");
require("dotenv").config();

async function registerNode() {
    const provider = new ethers.JsonRpcProvider(process.env.BASE_MAINNET_RPC);
    const wallet = new ethers.Wallet(process.env.NODE_PRIVATE_KEY, provider);
    
    const nodeRegistryABI = [
        "function registerNode(string _peerId, string[] _models, string _region) payable"
    ];
    
    const nodeRegistry = new ethers.Contract(
        process.env.NODE_REGISTRY_ADDRESS,
        nodeRegistryABI,
        wallet
    );
    
    // Get supported models from config
    const models = config.models.supported.map(m => m.id);
    
    console.log("Registering node...");
    console.log("Peer ID:", config.node.peerId);
    console.log("Models:", models);
    console.log("Region:", config.node.region);
    console.log("Stake: 100 ETH");
    
    const tx = await nodeRegistry.registerNode(
        config.node.peerId,
        models,
        config.node.region,
        { 
            value: ethers.parseEther("100"),
            gasLimit: 500000
        }
    );
    
    console.log("Transaction sent:", tx.hash);
    const receipt = await tx.wait();
    console.log("Node registered successfully!");
}

registerNode().catch(console.error);
```

### Run Registration
```bash
node scripts/register-node.js
```

## Step 5: Start Node Services

### Start All Services
```bash
# Start services with Docker Compose
docker-compose up -d

# Check logs
docker-compose logs -f job-manager

# Verify all services are running
docker-compose ps
```

### Verify Node Health
```bash
# Check IPFS
curl http://localhost:5001/api/v0/id

# Check model service
curl http://localhost:8001/health

# Check job manager
curl http://localhost:3000/health

# Check metrics
curl http://localhost:9090/metrics
```

## Step 6: Configure Job Processing

### Job Manager Configuration
The job manager automatically:
1. Monitors blockchain for available jobs
2. Claims jobs matching your capabilities
3. Processes jobs using appropriate models
4. Submits results and proofs

### Configure Job Selection Strategy
Create `config/strategy.json`:
```json
{
  "selection": {
    "minPayment": "0.001",
    "maxConcurrentJobs": 10,
    "preferredModels": ["gpt-4", "llama-2-70b"],
    "regionPreference": "same",
    "reputationThreshold": 100
  },
  "processing": {
    "timeout": 3600,
    "retryAttempts": 3,
    "proofGeneration": true
  },
  "optimization": {
    "batchSize": 5,
    "cacheResults": true,
    "compressionEnabled": true
  }
}
```

## Monitoring and Maintenance

### Set Up Monitoring Dashboard
```bash
# Install Grafana
docker run -d \
  -p 3001:3000 \
  --name=grafana \
  -v grafana-storage:/var/lib/grafana \
  grafana/grafana

# Configure Prometheus
# Add to docker-compose.yml
```

### Monitor Key Metrics
- **GPU Utilization**: Target 80-90%
- **Job Success Rate**: Should be >95%
- **Response Time**: <30s for most jobs
- **Reputation Score**: Monitor trends
- **Earnings**: Track daily/weekly

### Automated Alerts
Create `monitoring/alerts.js`:
```javascript
const monitoring = {
  checks: [
    {
      name: "GPU Temperature",
      threshold: 85,
      action: "throttle"
    },
    {
      name: "Failed Jobs",
      threshold: 3,
      action: "notify"
    },
    {
      name: "Low Balance",
      threshold: "0.1 ETH",
      action: "alert"
    }
  ]
};
```

## Security Best Practices

### 1. Secure Your Keys
```bash
# Use hardware wallet for mainnet
# Or use encrypted key storage
npm install @metamask/eth-sig-util

# Encrypt private key
node scripts/encrypt-key.js
```

### 2. Firewall Configuration
```bash
# Allow only necessary ports
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp  # SSH
sudo ufw allow 3000/tcp  # Job manager API
sudo ufw allow 9090/tcp  # Metrics
sudo ufw enable
```

### 3. Regular Updates
```bash
# Create update script
#!/bin/bash
cd ~/fabstir-node
git pull
npm install
docker-compose pull
docker-compose up -d
```

## Troubleshooting

### Common Issues

#### GPU Not Detected
```bash
# Check NVIDIA driver
nvidia-smi

# Check Docker GPU access
docker run --rm --gpus all nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi
```

#### Job Claiming Fails
```bash
# Check node registration
cast call $NODE_REGISTRY_ADDRESS "isActiveNode(address)" $YOUR_ADDRESS

# Check reputation
cast call $REPUTATION_SYSTEM_ADDRESS "getReputation(address)" $YOUR_ADDRESS
```

#### Model Loading Issues
```bash
# Check available memory
free -h

# Check GPU memory
nvidia-smi --query-gpu=memory.free --format=csv

# Clear cache if needed
rm -rf ~/.cache/huggingface
```

## Performance Optimization

### 1. Model Optimization
```python
# Use quantization for larger models
from transformers import AutoModelForCausalLM, BitsAndBytesConfig

quantization_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_compute_dtype=torch.float16
)

model = AutoModelForCausalLM.from_pretrained(
    "meta-llama/Llama-2-70b-chat-hf",
    quantization_config=quantization_config
)
```

### 2. Batch Processing
```javascript
// Process multiple jobs together
async function batchProcess(jobs) {
    const batchSize = 5;
    const batches = [];
    
    for (let i = 0; i < jobs.length; i += batchSize) {
        batches.push(jobs.slice(i, i + batchSize));
    }
    
    for (const batch of batches) {
        await Promise.all(batch.map(processJob));
    }
}
```

### 3. Caching Strategy
```javascript
const cache = new Map();

function getCachedResult(inputHash) {
    return cache.get(inputHash);
}

function cacheResult(inputHash, result) {
    cache.set(inputHash, result);
    // Implement LRU eviction
}
```

## Earning Optimization

### 1. Multi-Model Support
Support more models to access more jobs:
```javascript
const models = [
    "gpt-4",
    "gpt-3.5-turbo",
    "claude-2",
    "llama-2-70b",
    "mistral-7b",
    "stable-diffusion-xl"
];
```

### 2. Regional Expansion
Consider running nodes in multiple regions:
- Lower latency for regional jobs
- Access to region-specific jobs
- Redundancy and failover

### 3. Reputation Building
- Maintain >99% success rate
- Fast response times
- Participate in governance
- Provide quality results

## Next Steps

1. **[Staking Guide](staking-guide.md)** - Optimize your stake
2. **[Claiming Jobs](claiming-jobs.md)** - Advanced job selection
3. **[Monitoring Setup](../advanced/monitoring-setup.md)** - Production monitoring

## Resources

- [Fabstir Node Repository](https://github.com/fabstir/fabstir-node)
- [Model Optimization Guide](https://huggingface.co/docs/optimum)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/)
- [Base Network Status](https://status.base.org)

---

Need help? Join our [Discord](https://discord.gg/fabstir) for node operator support →