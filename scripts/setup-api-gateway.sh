#!/bin/bash
# =============================================================================
# Manual Setup Script — API Gateway (VM 3)
# =============================================================================
# Use this if user_data didn't run, or to manually set up Nginx.
#
# Usage:
#   ssh -i devops-key.pem ubuntu@<API_GW_PUBLIC_IP>
#   sudo bash /opt/app/scripts/setup-api-gateway.sh <CALLER_WORKER_PRIVATE_IP>

set -euo pipefail

CALLER_IP="${1:?Usage: $0 <CALLER_WORKER_PRIVATE_IP>}"

echo "Setting up API Gateway with Nginx..."
echo "Caller worker IP: $CALLER_IP"

# Install Nginx
sudo apt-get update -y
sudo apt-get install -y nginx

# Configure reverse proxy
sudo tee /etc/nginx/sites-available/default > /dev/null << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    location /health {
        return 200 '{"status": "ok"}';
        add_header Content-Type application/json;
    }

    location / {
        proxy_pass http://$CALLER_IP:3111;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }
}
EOF

sudo nginx -t
sudo systemctl enable nginx
sudo systemctl restart nginx

echo "✅ API Gateway setup complete!"
echo "Nginx forwarding to caller worker at $CALLER_IP:3111"
