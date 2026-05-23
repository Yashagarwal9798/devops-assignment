## Verification

Public health check:

<img width="1047" height="96" alt="heathcheck" src="https://github.com/user-attachments/assets/8e0675a8-8cbd-4bd9-a099-60491b4ff020" />

<img width="1600" height="756" alt="awscheck" src="https://github.com/user-attachments/assets/372bb2f1-48f9-4fc5-904f-ee6cdb7dc1d7" />


# Distributed Inference Mesh - DevOps Assignment

This repository deploys the `quickstart` iii worker project on AWS as a small
distributed inference system. The worker VMs live in a private subnet, communicate
over private IPs, and expose inference through a single public JSON HTTP endpoint.

## Architecture

```text
                         Internet
                            |
                            v
                 +----------------------+
                 | API Gateway VM       |
                 | Public subnet        |
                 | Nginx :80            |
                 | Public IP            |
                 +----------+-----------+
                            |
                            | reverse proxy to 10.0.2.x:3111
                            v
+------------------------------------------------------------------+
| VPC 10.0.0.0/16                                                   |
|                                                                  |
| Public subnet 10.0.1.0/24                                        |
| - API Gateway VM                                                  |
| - NAT Gateway                                                     |
| - Internet Gateway route                                          |
|                                                                  |
| Private subnet 10.0.2.0/24                                       |
|                                                                  |
|   +-------------------------+      iii RPC / worker connection    |
|   | Caller Worker VM        | <----------------------------------+ |
|   | TypeScript worker       |                                    | |
|   | iii engine :49134       |                                    | |
|   | iii-http :3111          |                                    | |
|   +------------+------------+                                    | |
|                |                                                 | |
|                | triggers inference::run_inference               | |
|                v                                                 | |
|   +-------------------------+                                    | |
|   | Inference Worker VM     | -----------------------------------+ |
|   | Python worker           |                                      |
|   | gemma-3-270m GGUF       |                                      |
|   | no public IP            |                                      |
|   +-------------------------+                                      |
|                                                                  |
+------------------------------------------------------------------+
```

## AWS Resources

Terraform provisions:

| Resource | Purpose |
| --- | --- |
| VPC `10.0.0.0/16` | Isolated network for the deployment |
| Public subnet `10.0.1.0/24` | Hosts the API gateway and NAT gateway |
| Private subnet `10.0.2.0/24` | Hosts the caller and inference worker VMs |
| Internet Gateway | Gives the public subnet internet access |
| NAT Gateway | Gives private VMs outbound-only internet access for packages/model downloads |
| Security groups | Expose only the API gateway publicly; keep workers private |
| EC2 API gateway | Nginx reverse proxy, public entry point |
| EC2 caller worker | iii engine, iii-http, TypeScript worker |
| EC2 inference worker | Python model worker |

## VM Layout

| VM | Subnet | Instance type | Public IP | Main process |
| --- | --- | --- | --- | --- |
| API Gateway | Public | `t3.micro` | Yes | Nginx on port `80` |
| Caller Worker | Private | `t3.micro` | No | iii engine on `49134`, iii-http on `3111` |
| Inference Worker | Private | `t3.large` | No | Python worker connected to caller engine |

The inference worker uses `III_URL=ws://<caller_private_ip>:49134`, so it
registers with the caller VM's iii engine over the private subnet. The public
internet never talks directly to either worker VM.

## Request Flow

1. A client sends `POST /v1/chat/completions` to the API gateway public IP.
2. Nginx forwards the request to the caller worker VM on private port `3111`.
3. The TypeScript caller worker handles the HTTP trigger.
4. The caller worker invokes `inference::run_inference`.
5. The Python inference worker runs `gemma-3-270m` and returns the response.
6. The response flows back through caller worker, Nginx, and then to the client.

## API

Endpoint:

```text
POST http://<API_GATEWAY_PUBLIC_IP>/v1/chat/completions
```

Request:

```bash
curl -X POST "http://<API_GATEWAY_PUBLIC_IP>/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"What is 2+2? Answer briefly."}]}'
```

Expected response shape:

```json
{
  "id": "chatcmpl-gemma-3-270m",
  "object": "chat.completion",
  "model": "ggml-org/gemma-3-270m-GGUF",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "2 + 2 equals 4."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 12,
    "completion_tokens": 8,
    "total_tokens": 20
  }
}
```

Health check for the public Nginx gateway:

```bash
curl "http://<API_GATEWAY_PUBLIC_IP>/health"
```

Expected:

```json
{"status":"ok"}
```

## Deployment

Prerequisites:

- AWS account and AWS CLI credentials
- Terraform `>= 1.0`
- Git

Deploy:

```bash
git clone https://github.com/Yashagarwal9798/devops-assignment.git
cd devops-assignment/terraform
terraform init
terraform plan
terraform apply
```

Terraform outputs:

- `api_gateway_public_ip`
- `api_endpoint`
- `caller_worker_private_ip`
- `inference_worker_private_ip`
- SSH commands for all VMs
- Ready-to-run curl command

Wait several minutes after `terraform apply`. The EC2 `user_data` scripts install
packages, install iii, clone this repo, install worker dependencies, and create
systemd services.

## Operations

SSH from the `terraform/` directory after apply:

```bash
ssh -i devops-key.pem ubuntu@<API_GATEWAY_PUBLIC_IP>

ssh -i devops-key.pem -o IdentitiesOnly=yes \
  -o ProxyJump=ubuntu@<API_GATEWAY_PUBLIC_IP> \
  ubuntu@<CALLER_WORKER_PRIVATE_IP>

ssh -i devops-key.pem -o IdentitiesOnly=yes \
  -o ProxyJump=ubuntu@<API_GATEWAY_PUBLIC_IP> \
  ubuntu@<INFERENCE_WORKER_PRIVATE_IP>
```

Check services:

```bash
# API gateway VM
sudo systemctl status nginx --no-pager -l

# Caller worker VM
sudo systemctl status iii-caller --no-pager -l
sudo journalctl -u iii-caller -n 100 --no-pager
sudo ss -lntp | grep -E '3111|49134'

# Inference worker VM
sudo systemctl status iii-inference --no-pager -l
sudo journalctl -u iii-inference -n 100 --no-pager
```

## Repository Structure

```text
devops-assignment/
|-- README.md
|-- WRITEUP.md
|-- quickstart/
|   |-- config.yaml
|   `-- workers/
|       |-- caller-worker/
|       |   |-- src/worker.ts
|       |   |-- package.json
|       |   `-- iii.worker.yaml
|       `-- inference-worker/
|           |-- inference_worker.py
|           |-- requirements.txt
|           `-- iii.worker.yaml
|-- terraform/
|   |-- main.tf
|   |-- variables.tf
|   |-- vpc.tf
|   |-- security_groups.tf
|   |-- ec2.tf
|   |-- key.tf
|   |-- outputs.tf
|   `-- userdata/
|       |-- setup-api-gateway.sh
|       |-- setup-caller-worker.sh
|       `-- setup-inference-worker.sh
|-- scripts/
|   |-- setup-api-gateway.sh
|   |-- setup-caller-worker.sh
|   `-- setup-inference-worker.sh
`-- systemd/
    |-- iii-caller.service
    `-- iii-inference.service
```

## Security Notes

- Worker instances have no public IPs.
- Only the API gateway is publicly reachable.
- Worker security group allows internal VPC traffic and SSH only from the API gateway security group.
- Private workers use a NAT Gateway for outbound package/model downloads.
- Terraform state, SSH keys, `.tfvars`, and local credentials are ignored by `.gitignore`.

## Tear Down

Destroy the stack when not testing to avoid EC2 and NAT Gateway charges:

```bash
cd terraform
terraform destroy
```

## Verification Evidence

The public health check was validated with:

```bash
curl "http://<API_GATEWAY_PUBLIC_IP>/health"
```

Screenshots can be added after redacting AWS account ID, usernames, public IPs,
private IPs, and EC2 instance IDs.
