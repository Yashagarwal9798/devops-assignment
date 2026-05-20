#!/bin/bash
# =============================================================================
# Inference Worker VM Bootstrap Script (VM 1 — Private Subnet)
# =============================================================================
# This script runs automatically when the VM boots (via EC2 user_data).
# It installs Python, dependencies, the iii engine, clones the repo,
# and starts the inference worker as a systemd service.

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
apt-get install -y python3 python3-pip python3-venv git curl

# ---------------------------------------------------------------------------
# 3. Install the iii engine (the RPC/messaging runtime)
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
pip3 install --break-system-packages -r requirements.txt

# ---------------------------------------------------------------------------
# 6. Create the iii engine config for this VM
#    - Only the inference worker runs on this VM
#    - iii-http is NOT needed here (it runs on the caller-worker VM)
#    - Engine listens on 0.0.0.0:49134 so remote workers can connect
# ---------------------------------------------------------------------------
mkdir -p /opt/app/quickstart/data
cat > /opt/app/config-inference.yaml << 'ENGINECONFIG'
workers:
  - name: iii-observability
    config:
      enabled: true
      service_name: iii-inference
      exporter: memory
      memory_max_spans: 10000
      metrics_enabled: true
      metrics_exporter: memory
      logs_enabled: true
      logs_exporter: memory
      logs_console_output: true
      sampling_ratio: 1.0

  - name: iii-queue
    config:
      adapter:
        name: builtin

  - name: iii-state
    config:
      adapter:
        name: kv
        config:
          store_method: file_based
          file_path: /opt/app/quickstart/data/state_store.db

  - name: inference-worker
    worker_path: /opt/app/quickstart/workers/inference-worker
ENGINECONFIG

# ---------------------------------------------------------------------------
# 7. Create systemd service for the iii engine + inference worker
# ---------------------------------------------------------------------------
cat > /etc/systemd/system/iii-inference.service << 'SERVICEEOF'
[Unit]
Description=iii Engine with Inference Worker
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/app/quickstart
Environment=III_HOST=0.0.0.0
ExecStart=/usr/local/bin/iii engine start --config /opt/app/config-inference.yaml
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICEEOF

# ---------------------------------------------------------------------------
# 8. Enable and start the service
# ---------------------------------------------------------------------------
systemctl daemon-reload
systemctl enable iii-inference.service
systemctl start iii-inference.service

echo "========================================="
echo "Inference Worker setup complete!"
echo "Finished at: $(date)"
echo "========================================="
