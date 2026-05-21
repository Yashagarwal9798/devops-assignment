#!/bin/bash
# =============================================================================
# Inference Worker VM Bootstrap Script (VM 1 — Private Subnet)
# =============================================================================
# This script runs automatically when the VM boots (via EC2 user_data).
# It installs Python dependencies, clones the repo, and starts the Python
# inference worker pointed at the caller VM's iii engine over the private subnet.

set -euo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

echo "========================================="
echo "Setting up Inference Worker VM"
echo "Started at: $(date)"
echo "========================================="

# ---------------------------------------------------------------------------
# 1. System updates
# ---------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

# ---------------------------------------------------------------------------
# 2. Install Python 3 and required system packages
# ---------------------------------------------------------------------------
apt-get install -y python3 python3-pip python3-venv git curl jq

# ---------------------------------------------------------------------------
# 3. Install the iii CLI for debugging parity with the caller VM
# ---------------------------------------------------------------------------
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
# Add iii to PATH for all users
ln -sf /root/.iii/bin/iii /usr/local/bin/iii || true

# ---------------------------------------------------------------------------
# 4. Clone the project repository
# ---------------------------------------------------------------------------
cd /opt
git clone ${github_repo_url} app || true
cd /opt/app/quickstart

# ---------------------------------------------------------------------------
# 5. Install Python dependencies for the inference worker
# ---------------------------------------------------------------------------
cd /opt/app/quickstart/workers/inference-worker
python3 -m venv /opt/app/venv
/opt/app/venv/bin/pip install --upgrade pip
/opt/app/venv/bin/pip install -r requirements.txt

# ---------------------------------------------------------------------------
# 6. Create systemd service for the inference worker process
#    The caller VM owns the iii engine and HTTP server. This VM only runs the
#    Python worker, connecting to the caller engine on the private subnet.
# ---------------------------------------------------------------------------
cat > /etc/systemd/system/iii-inference.service << SERVICEEOF
[Unit]
Description=iii Inference Worker
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/app/quickstart/workers/inference-worker
Environment=III_URL=ws://${caller_worker_private_ip}:49134
ExecStartPre=/bin/bash -c 'until timeout 2 bash -c "</dev/tcp/${caller_worker_private_ip}/49134"; do echo "waiting for caller engine at ${caller_worker_private_ip}:49134"; sleep 5; done'
ExecStart=/opt/app/venv/bin/python inference_worker.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
LimitNOFILE=65536
MemoryMax=8G

[Install]
WantedBy=multi-user.target
SERVICEEOF

# ---------------------------------------------------------------------------
# 7. Enable and start the service
# ---------------------------------------------------------------------------
systemctl daemon-reload
systemctl enable iii-inference.service
systemctl start iii-inference.service

echo "========================================="
echo "Inference Worker setup complete!"
echo "Finished at: $(date)"
echo "========================================="
