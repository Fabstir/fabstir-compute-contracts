#!/bin/bash

echo "🎯 FABSTIR CONTRACT DEPLOYMENT SETUP"
echo "===================================="
echo ""

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is not installed. Please install Node.js first:"
    echo "   https://nodejs.org/"
    exit 1
fi

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    echo "❌ npm is not installed. Please install npm first."
    exit 1
fi

echo "✅ Node.js version: $(node --version)"
echo "✅ npm version: $(npm --version)"
echo ""

# Install dependencies
echo "📦 Installing dependencies..."
npm install
echo ""

# Compile contracts if forge is available
if command -v forge &> /dev/null; then
    echo "🔨 Compiling contracts with Forge..."
    forge build
    echo ""
else
    echo "⚠️  Forge not found. Make sure contracts are compiled before running deployment."
    echo "   If you have Foundry installed elsewhere, run 'forge build' first."
    echo ""
fi

# Check if artifacts exist
if [ -d "out" ] && [ -f "out/PaymentEscrowWithEarnings.sol/PaymentEscrowWithEarnings.json" ]; then
    echo "✅ Contract artifacts found"
    echo ""
    
    echo "🚀 Ready to deploy! Run:"
    echo "   npm run deploy"
    echo ""
    echo "Or directly:"
    echo "   node deploy-contracts.js"
else
    echo "❌ Contract artifacts not found in 'out/' directory"
    echo ""
    echo "Please make sure to compile contracts first:"
    echo "   forge build"
    echo ""
    echo "The deployment script expects these files:"
    echo "   - out/PaymentEscrowWithEarnings.sol/PaymentEscrowWithEarnings.json"
    echo "   - out/JobMarketplaceFABWithEarnings.sol/JobMarketplaceFABWithEarnings.json"
fi

echo ""
echo "📋 Configuration summary:"
echo "   🌐 Network: Base Sepolia" 
echo "   🏦 Treasury: 0x4e770e723B95A0d8923Db006E49A8a3cb0BAA078"
echo "   💰 Platform Fee: 10%"
echo "   🔑 Using deployer: 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11"