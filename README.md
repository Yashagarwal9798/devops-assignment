# Distributed Inference Mesh — DevOps Assignment

Deploy the [iii quickstart](https://iii.dev/docs/quickstart) distributed inference system across multiple VMs on AWS, with network isolation, reproducible infrastructure, and a public JSON API endpoint.

## Architecture

```
                          Internet
                             │
                             ▼
┌────────────────────────────────────────────────────────────┐
│                    VPC (10.0.0.0/16)                       │
│                                                            │
│  ┌──────────────────────┐    ┌───────────────────────────┐ │
│  │  Public Subnet        │    │  Private Subnet            │ │
│  │  10.0.1.0/24          │    │  10.0.2.0/24               │ │
│  │                       │    │                             │ │
│  │  ┌─────────────────┐  │    │  ┌───────────────────────┐ │ │
│  │  │ VM 3: API GW    │  │    │  │ VM 2: Caller Worker   │ │ │
│  │  │ (t3.micro)      │──│────│──│ (TypeScript)          │ │ │
│  │  │ Nginx :80       │  │    │  │ iii-http :3111        │ │ │
│  │  │ Public IP ✓     │  │    │  │ No public IP          │ │ │
│  │  └─────────────────┘  │    │  └───────────┬───────────┘ │ │
│  │                       │    │              │ RPC :49134   │ │
│  │  ┌─────────────────┐  │    │  ┌───────────▼───────────┐ │ │
│  │  │ NAT Gateway     │  │    │  │ VM 1: Inference       │ │ │
│  │  │ (outbound only) │──│────│──│ Worker (Python)       │ │ │
│  │  │                 │  │    │  │ gemma-3-270m (GGUF)   │ │ │
│  │  └─────────────────┘  │    │  │ t3.large (8GB RAM)    │ │ │
│  │                       │    │  │ No public IP          │ │ │
│  └──────────────────────┘    │  └───────────────────────┘ │ │
│                               └───────────────────────────┘ │
│  Internet Gateway ←→ Public Subnet only                     │
└────────────────────────────────────────────────────────────┘
```

### Request Flow

1. User sends `POST /v1/chat/completions` to the API Gateway (public IP, port 80)
2. Nginx reverse proxy forwards the request to the **caller worker** (private IP, port 3111)
3. The caller worker's `http::run_inference_over_http` function receives the request
4. It calls `inference::get_response` which triggers `inference::run_inference` via RPC
5. The **inference worker** (on a separate VM) loads the `gemma-3-270m` model and generates text
6. The result flows back: inference worker → caller worker → Nginx → user

### Network Security

- **Workers (VM 1, VM 2):** Private subnet — no public IP, no direct internet access
- **API Gateway (VM 3):** Public subnet — only port 80 (HTTP) and port 22 (SSH) exposed
- **NAT Gateway:** Allows private VMs to download packages/models (outbound only)
- **Security Groups:** Workers accept traffic only from within the VPC (`10.0.0.0/16`)

---

## API Documentation

### Endpoint

```
POST http://<API_GATEWAY_PUBLIC_IP>/v1/chat/completions
```

### Request

```bash
curl -X POST http://<API_GATEWAY_PUBLIC_IP>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "What is 2+2?"}
    ]
  }'
```

### Request Schema

```json
{
  "messages": [
    {
      "role": "user | system | assistant",
      "content": "Your message text"
    }
  ]
}
```

### Response Schema

```json
{
  "result": {
    "success": "...",
    "<model_output>": "The model's generated text response"
  }
}
```

### Sample Response

```json
{
  "result": {
    "success": "You've connected two workers and they're interoperating seamlessly...",
    "response": "2 + 2 equals 4."
  }
}
```

### Health Check

```bash
curl http://<API_GATEWAY_PUBLIC_IP>/health
# Returns: {"status": "ok"}
```

---

## Prerequisites

- **AWS Account** with programmatic access (Access Key + Secret Key)
- **Terraform** >= 1.0 ([install](https://developer.hashicorp.com/terraform/downloads))
- **AWS CLI** v2 ([install](https://aws.amazon.com/cli/))

---

## Deployment Instructions (From Scratch)

### 1. Configure AWS CLI

```bash
aws configure
# AWS Access Key ID: <your-key>
# AWS Secret Access Key: <your-secret>
# Default region name: ap-south-1
# Default output format: json
```

### 2. Clone the Repository

```bash
git clone https://github.com/Yashagarwal9798/devops-assignment.git
cd devops-assignment
```

### 3. Deploy with Terraform

```bash
cd terraform

# Initialize Terraform (downloads AWS provider)
terraform init

# Preview the resources that will be created
terraform plan

# Create everything (type "yes" when prompted)
terraform apply
```

Terraform will output:
- `api_gateway_public_ip` — the public IP for API requests
- `inference_worker_private_ip` — internal IP of inference worker
- `caller_worker_private_ip` — internal IP of caller worker
- `test_curl_command` — ready-to-use curl command

### 4. Wait for Bootstrap (~5-10 minutes)

The VMs run setup scripts automatically on boot (user_data). They:
- Install dependencies (Python/Node.js)
- Install the iii engine
- Clone the repo and install worker dependencies
- Start the workers as systemd services

### 5. Verify the Deployment

```bash
# Check if API gateway is responding
curl http://<API_GATEWAY_PUBLIC_IP>/health

# Test inference (may take a moment on first run — model download)
curl -X POST http://<API_GATEWAY_PUBLIC_IP>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "What is 2+2?"}]}'
```

### 6. SSH Access (for debugging)

```bash
# SSH into API gateway (bastion host)
ssh -i terraform/devops-key.pem ubuntu@<API_GATEWAY_PUBLIC_IP>

# From the API gateway, SSH into private VMs
ssh -i devops-key.pem ubuntu@<INFERENCE_WORKER_PRIVATE_IP>
ssh -i devops-key.pem ubuntu@<CALLER_WORKER_PRIVATE_IP>

# Check worker logs
sudo journalctl -u iii-inference -f   # On inference worker VM
sudo journalctl -u iii-caller -f      # On caller worker VM
```

### 7. Tear Down (IMPORTANT — avoid charges)

```bash
cd terraform
terraform destroy
# Type "yes" to confirm
```

> ⚠️ **Always destroy resources when not testing.** The NAT Gateway alone costs ~$0.045/hour.

---

## Repository Structure

```
devops-assignment/
├── README.md                           ← This file
├── WRITEUP.md                          ← Production hardening & scaling discussion
├── quickstart/                         ← Application code (from Alchemyst AI)
│   ├── config.yaml                     ← iii engine configuration
│   └── workers/
│       ├── inference-worker/           ← Python — loads gemma-3-270m model
│       │   ├── inference_worker.py
│       │   ├── requirements.txt
│       │   └── iii.worker.yaml
│       └── caller-worker/              ← TypeScript — API router / RPC caller
│           ├── src/worker.ts
│           ├── package.json
│           └── iii.worker.yaml
├── terraform/                          ← Infrastructure as Code
│   ├── main.tf                         ← AWS provider configuration
│   ├── variables.tf                    ← Configurable parameters
│   ├── vpc.tf                          ← VPC, subnets, IGW, NAT GW, route tables
│   ├── security_groups.tf              ← Firewall rules (API vs workers)
│   ├── ec2.tf                          ← EC2 instances (3 VMs)
│   ├── key.tf                          ← SSH key pair generation
│   ├── outputs.tf                      ← Deployment outputs (IPs, curl command)
│   └── userdata/                       ← VM bootstrap scripts (run on boot)
│       ├── setup-inference-worker.sh
│       ├── setup-caller-worker.sh
│       └── setup-api-gateway.sh
├── scripts/                            ← Manual setup scripts (fallback)
│   ├── setup-inference-worker.sh
│   ├── setup-caller-worker.sh
│   └── setup-api-gateway.sh
├── systemd/                            ← Systemd unit files
│   ├── iii-inference.service
│   └── iii-caller.service
└── .gitignore                          ← Excludes secrets, keys, tfstate
```

---

## Technology Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Cloud Provider | AWS (ap-south-1) | Infrastructure hosting |
| IaC | Terraform | Reproducible infrastructure |
| Networking | VPC, Subnets, NAT GW | Network isolation |
| Compute | EC2 (t3.large + t3.micro) | Virtual machines |
| Reverse Proxy | Nginx | HTTP routing / load balancing |
| RPC Framework | [iii](https://iii.dev) | Cross-language worker mesh |
| ML Model | gemma-3-270m (GGUF Q8) | Small language model |
| Process Manager | systemd | Service lifecycle management |

---

## Author

**Yash Agarwal**  
DevOps Internship Assignment — Alchemyst AI
