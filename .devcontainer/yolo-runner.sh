#!/bin/bash
# Copyright (c) 2025 Fabstir
# SPDX-License-Identifier: BUSL-1.1
# fabstir-compute-contracts/.devcontainer/yolo-runner.sh

echo "🚀 Fabstir Contracts YOLO Mode"
echo "=============================="

# Initialize if needed
if [ ! -f "foundry.toml" ]; then
    forge init --force --no-git
fi

# Install dependencies (without --no-commit flag)
if [ ! -d "lib/openzeppelin-contracts" ]; then
    forge install OpenZeppelin/openzeppelin-contracts
    forge install base-org/contracts || true
fi

# Start test watcher
exec /usr/local/bin/test-watcher.sh
