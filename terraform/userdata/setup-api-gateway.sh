#!/bin/bash
# =============================================================================
# API Gateway VM Bootstrap Script (VM 3 — Public Subnet)
# =============================================================================
# This script runs automatically when the VM boots (via EC2 user_data).
# It installs Nginx and configures it as a reverse proxy that forwards
# HTTP requests to the caller worker's iii-http server (port 3111).

set -euo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

echo "========================================="
echo "Setting up API Gateway VM"
echo "Started at: $(date)"
echo "========================================="

# ---------------------------------------------------------------------------
# 1. System updates
# ---------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

# ---------------------------------------------------------------------------
# 2. Install Nginx
# ---------------------------------------------------------------------------
apt-get install -y nginx

# ---------------------------------------------------------------------------
# 3. Configure Nginx as a reverse proxy
#    - Listens on port 80 (public)
#    - Forwards all requests to the caller worker's iii-http on port 3111
#    - The caller_worker_private_ip is injected by Terraform templatefile()
# ---------------------------------------------------------------------------
cat > /etc/nginx/sites-available/default << 'NGINXEOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    # Health check endpoint
    location /health {
        return 200 '{"status": "ok"}';
        add_header Content-Type application/json;
    }

    # Forward all API requests to the caller worker's iii-http server
    location / {
        proxy_pass http://${caller_worker_private_ip}:3111;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }
}
NGINXEOF

# ---------------------------------------------------------------------------
# 4. Enable and restart Nginx
# ---------------------------------------------------------------------------
nginx -t  # Test config before restarting
systemctl enable nginx
systemctl restart nginx

echo "========================================="
echo "API Gateway setup complete!"
echo "Nginx forwarding to caller worker at ${caller_worker_private_ip}:3111"
echo "Finished at: $(date)"
echo "========================================="
