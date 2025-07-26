#!/bin/bash
# fabstir-compute-contracts/.devcontainer/yolo-runner.sh

echo "🚀 Fabstir Contracts YOLO Mode"
echo "=============================="

# Initialize if needed
if [ ! -f "foundry.toml" ]; then
    forge init --force --no-git
fi

# Install dependencies
if [ ! -d "lib/openzeppelin-contracts" ]; then
    forge install OpenZeppelin/openzeppelin-contracts --no-commit
    forge install base-org/contracts --no-commit
fi

# Start test watcher
exec /usr/local/bin/test-watcher.sh