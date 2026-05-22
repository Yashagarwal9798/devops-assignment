#!/bin/bash
# =============================================================================
# Manual Setup Script - Inference Worker (VM 1)
# =============================================================================
# Use this if user_data didn't run, or to manually set up the inference worker.
#
# Usage:
#   ssh -i devops-key.pem -o ProxyJump=ubuntu@<API_GW_IP> ubuntu@<INFERENCE_IP>
#   sudo bash /opt/app/scripts/setup-inference-worker.sh <CALLER_WORKER_PRIVATE_IP>

set -euo pipefail

CALLER_IP="${1:?Usage: $0 <CALLER_WORKER_PRIVATE_IP>}"

echo "Installing inference worker dependencies..."
echo "Caller engine IP: $CALLER_IP"

sudo apt-get -o Acquire::ForceIPv4=true update -y
sudo apt-get install -y python3 python3-pip python3-venv git curl jq

curl -fsSL https://install.iii.dev/iii/main/install.sh | bash
sudo ln -sf /root/.local/bin/iii /usr/local/bin/iii || true

if [ ! -d /opt/app ]; then
    cd /opt
    sudo git clone https://github.com/Yashagarwal9798/devops-assignment.git app
fi

cd /opt/app/quickstart/workers/inference-worker
sudo python3 -m venv /opt/app/venv
sudo /opt/app/venv/bin/pip install --upgrade pip
sudo /opt/app/venv/bin/pip install -r requirements.txt

sudo tee /etc/systemd/system/iii-inference.service > /dev/null << EOF
[Unit]
Description=iii Inference Worker
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/app/quickstart/workers/inference-worker
Environment=III_URL=ws://$CALLER_IP:49134
ExecStartPre=/bin/bash -c 'until timeout 2 bash -c "</dev/tcp/$CALLER_IP/49134"; do echo "waiting for caller engine at $CALLER_IP:49134"; sleep 5; done'
ExecStart=/opt/app/venv/bin/python inference_worker.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
LimitNOFILE=65536
MemoryMax=8G

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable iii-inference.service
sudo systemctl restart iii-inference.service

echo "Inference worker service started and connected to ws://$CALLER_IP:49134"
