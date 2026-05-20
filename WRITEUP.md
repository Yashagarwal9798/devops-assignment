# Production Hardening & Scaling Writeup

## What Would You Harden Before Putting This in Production?

### 1. TLS/HTTPS Termination
The current setup serves traffic over plain HTTP. In production, I would:
- Obtain an SSL certificate via AWS Certificate Manager (ACM) — it's free for AWS resources
- Place an Application Load Balancer (ALB) in front of the API gateway with HTTPS listeners
- Redirect all HTTP traffic to HTTPS
- Alternatively, use Let's Encrypt with certbot directly on the Nginx instance

### 2. Authentication & Authorization
The API endpoint is currently open to anyone. To secure it:
- Add API key authentication at the Nginx layer (check `X-API-Key` header)
- For multi-tenant use, implement JWT-based auth with AWS Cognito
- Rate-limit requests per API key to prevent abuse (Nginx `limit_req` module)

### 3. Network Security Hardening
- Restrict SSH access to specific IP ranges (currently open to `0.0.0.0/0` for debugging)
- Use AWS Systems Manager Session Manager instead of SSH for VM access (eliminates need for port 22)
- Enable VPC Flow Logs for network traffic auditing
- Use AWS WAF (Web Application Firewall) on the ALB to block malicious requests

### 4. Health Checks & Self-Healing
- Add application-level health check endpoints (`/health`) on each worker
- Configure ALB health checks to automatically route around unhealthy instances
- Set up Auto Scaling Groups (ASGs) to replace failed VMs automatically
- Add liveness/readiness probes for the iii engine processes

### 5. Logging & Monitoring
- Ship all logs to CloudWatch Logs using the CloudWatch agent
- Set up CloudWatch Alarms for: CPU > 80%, memory > 90%, 5xx error rate > 1%
- Create a CloudWatch Dashboard for real-time operational visibility
- Use AWS X-Ray or OpenTelemetry for distributed tracing across the worker mesh

### 6. Secrets Management
- Store sensitive configuration in AWS Secrets Manager or SSM Parameter Store
- Rotate credentials automatically
- Never store secrets in environment variables or code

### 7. Instance Hardening
- Use Amazon Linux 2023 or Ubuntu Pro for automatic security patches
- Enable IMDSv2 (Instance Metadata Service v2) to prevent SSRF attacks
- Apply the CIS benchmark for EC2 instances
- Use encrypted EBS volumes

---

## What Would You Do Differently If the Model Were 100× Larger?

A 100× larger model (e.g., 27B parameters instead of 270M) fundamentally changes the infrastructure requirements:

### 1. GPU Instances
- Switch from `t3.large` (CPU) to GPU instances: `g5.xlarge` (24GB VRAM, ~$1/hr) or `p3.2xlarge` (16GB V100)
- For models exceeding single-GPU VRAM, use multi-GPU instances like `g5.12xlarge` (4× A10G, 96GB total VRAM)
- Use Spot Instances for non-real-time batch inference to reduce costs by ~70%

### 2. Model Parallelism & Sharding
- Split the model across multiple GPUs using tensor parallelism (e.g., via vLLM or DeepSpeed)
- For models too large for a single machine, use pipeline parallelism across multiple nodes
- Consider using AWS SageMaker for managed model hosting with built-in model parallelism

### 3. Request Queuing & Async Processing
- Add an SQS queue between the API gateway and inference workers
- Implement async inference: return a `202 Accepted` with a job ID, allow polling for results
- This handles burst traffic without overloading the GPU instances

### 4. Container Orchestration
- Migrate from raw EC2 to Amazon EKS (Kubernetes) or ECS (Fargate)
- Package each worker as a Docker container for consistent deployment
- Use Kubernetes GPU scheduling to manage GPU allocation across inference pods
- Enables horizontal pod autoscaling based on queue depth or GPU utilization

### 5. Model Storage & Caching
- Store model weights on Amazon EFS (shared filesystem) or S3
- Mount EFS on all inference workers to avoid downloading the model on every instance
- Use instance store (NVMe SSD) for fast model loading from local cache

### 6. Inference Optimization
- Use quantization (GPTQ, AWQ, GGUF with lower bit precision) to reduce VRAM requirements
- Implement KV-cache optimization for multi-turn conversations
- Use continuous batching (vLLM) to maximize GPU throughput
- Consider ONNX Runtime or TensorRT for optimized inference

### 7. Cost Management
- Use Reserved Instances or Savings Plans for baseline GPU capacity
- Implement auto-scaling: scale up during business hours, scale down at night
- Use inference endpoints that scale to zero when idle (SageMaker Serverless Inference)
- Monitor per-request cost and set budget alerts

### 8. Multi-Region Deployment
- Deploy the inference mesh across multiple AWS regions for latency and redundancy
- Use Route 53 with latency-based routing to direct users to the nearest region
- Implement a global model registry for consistent deployments across regions
