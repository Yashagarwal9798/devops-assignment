#!/bin/bash
# =============================================================================
# Caller Worker VM Bootstrap Script (VM 2 — Private Subnet)
# =============================================================================
# This script runs automatically when the VM boots (via EC2 user_data).
# It installs Node.js, dependencies, the iii engine, clones the repo,
# and starts the caller worker as a systemd service.

set -euo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

echo "========================================="
echo "Setting up Caller Worker VM"
echo "Started at: $(date)"
echo "========================================="

# ---------------------------------------------------------------------------
# 1. System updates
# ---------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get -o Acquire::ForceIPv4=true update -y
apt-get upgrade -y

# ---------------------------------------------------------------------------
# 2. Install Node.js 20.x
# ---------------------------------------------------------------------------
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs git curl jq

# ---------------------------------------------------------------------------
# 3. Install the iii engine
# ---------------------------------------------------------------------------
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
ln -sf /root/.local/bin/iii /usr/local/bin/iii || true

# ---------------------------------------------------------------------------
# 4. Clone the project repository
# ---------------------------------------------------------------------------
cd /opt
git clone ${github_repo_url} app || true
cd /opt/app/quickstart

# ---------------------------------------------------------------------------
# 5. Install npm dependencies for the caller worker
# ---------------------------------------------------------------------------
cd /opt/app/quickstart/workers/caller-worker
npm install

# ---------------------------------------------------------------------------
# 6. Create the iii engine config for this VM
#    - The caller-worker runs here
#    - iii-http is enabled here (port 3111) — this serves the HTTP API
#    - Engine listens on 0.0.0.0:49134
#    - The inference worker is referenced remotely (connected via mesh)
# ---------------------------------------------------------------------------
mkdir -p /opt/app/quickstart/data
cat > /opt/app/config-caller.yaml << 'ENGINECONFIG'
workers:
  - name: iii-observability
    config:
      enabled: true
      service_name: iii-caller
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

  - name: iii-http
    config:
      port: 3111
      host: 0.0.0.0
      default_timeout: 120000
      concurrency_request_limit: 1024
      cors:
        allowed_origins:
        - '*'
        allowed_methods:
        - GET
        - POST
        - PUT
        - DELETE
        - OPTIONS

  - name: caller-worker
    worker_path: /opt/app/quickstart/workers/caller-worker
ENGINECONFIG

# ---------------------------------------------------------------------------
# 7. Create systemd service for the iii engine + caller worker
# ---------------------------------------------------------------------------
cat > /etc/systemd/system/iii-caller.service << 'SERVICEEOF'
[Unit]
Description=iii Engine with Caller Worker
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/app/quickstart
Environment=III_HOST=0.0.0.0
ExecStart=/usr/local/bin/iii --config /opt/app/config-caller.yaml
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
systemctl enable iii-caller.service
systemctl start iii-caller.service

echo "========================================="
echo "Caller Worker setup complete!"
echo "Finished at: $(date)"
echo "========================================="
