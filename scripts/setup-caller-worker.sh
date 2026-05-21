#!/bin/bash
# =============================================================================
# Manual Setup Script - Caller Worker (VM 2)
# =============================================================================
# Use this if user_data didn't run, or to manually set up the caller worker.
#
# Usage:
#   ssh -i devops-key.pem -o ProxyJump=ubuntu@<API_GW_IP> ubuntu@<CALLER_IP>
#   sudo bash /opt/app/scripts/setup-caller-worker.sh

set -euo pipefail

echo "Installing caller worker dependencies..."

sudo apt-get update -y
sudo apt-get install -y git curl jq

curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

curl -fsSL https://install.iii.dev/iii/main/install.sh | bash
sudo ln -sf ~/.iii/bin/iii /usr/local/bin/iii || true

if [ ! -d /opt/app ]; then
    cd /opt
    sudo git clone https://github.com/Yashagarwal9798/devops-assignment.git app
fi

cd /opt/app/quickstart/workers/caller-worker
npm install

sudo mkdir -p /opt/app/quickstart/data
sudo tee /opt/app/config-caller.yaml > /dev/null << 'EOF'
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
EOF

sudo tee /etc/systemd/system/iii-caller.service > /dev/null << 'EOF'
[Unit]
Description=iii Engine with Caller Worker (TypeScript) + HTTP Server
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/app/quickstart
Environment=III_HOST=0.0.0.0
ExecStart=/usr/local/bin/iii engine start --config /opt/app/config-caller.yaml
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable iii-caller.service
sudo systemctl restart iii-caller.service

echo "Caller worker service started on iii engine port 49134 and HTTP port 3111"
