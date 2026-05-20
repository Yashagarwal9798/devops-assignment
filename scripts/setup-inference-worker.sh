#!/bin/bash
# =============================================================================
# Manual Setup Script — Inference Worker (VM 1)
# =============================================================================
# Use this if user_data didn't run, or to manually set up the inference worker.
# Run on the inference worker VM after SSH'ing in via the bastion (API gateway).
#
# Usage:
#   ssh -i devops-key.pem -o ProxyJump=ubuntu@<API_GW_IP> ubuntu@<INFERENCE_IP>
#   sudo bash /opt/app/scripts/setup-inference-worker.sh

set -euo pipefail

echo "Installing inference worker dependencies..."

# System packages
sudo apt-get update -y
sudo apt-get install -y python3 python3-pip python3-venv git curl

# Install iii engine
curl -fsSL https://iii.dev/install.sh | bash
sudo ln -sf ~/.iii/bin/iii /usr/local/bin/iii || true

# Clone repo if not present
if [ ! -d /opt/app ]; then
    cd /opt
    sudo git clone https://github.com/Yashagarwal9798/devops-assignment.git app
fi

# Install Python dependencies
cd /opt/app/quickstart/workers/inference-worker
sudo pip3 install --break-system-packages -r requirements.txt

echo "✅ Inference worker dependencies installed!"
echo "Start with: sudo systemctl start iii-inference"
