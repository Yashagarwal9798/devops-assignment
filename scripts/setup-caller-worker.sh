#!/bin/bash
# =============================================================================
# Manual Setup Script — Caller Worker (VM 2)
# =============================================================================
# Use this if user_data didn't run, or to manually set up the caller worker.
#
# Usage:
#   ssh -i devops-key.pem -o ProxyJump=ubuntu@<API_GW_IP> ubuntu@<CALLER_IP>
#   sudo bash /opt/app/scripts/setup-caller-worker.sh

set -euo pipefail

echo "Installing caller worker dependencies..."

# System packages
sudo apt-get update -y
sudo apt-get install -y git curl

# Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install iii engine
curl -fsSL https://iii.dev/install.sh | bash
sudo ln -sf ~/.iii/bin/iii /usr/local/bin/iii || true

# Clone repo if not present
if [ ! -d /opt/app ]; then
    cd /opt
    sudo git clone https://github.com/Yashagarwal9798/devops-assignment.git app
fi

# Install npm dependencies
cd /opt/app/quickstart/workers/caller-worker
npm install

echo "✅ Caller worker dependencies installed!"
echo "Start with: sudo systemctl start iii-caller"
