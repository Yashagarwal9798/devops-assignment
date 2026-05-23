# Production Hardening and Scaling Writeup

## Production Hardening

This assignment deployment is intentionally small and simple: EC2 instances,
systemd services, Nginx, and Terraform. Before running it as a production
service, I would harden the following areas.

### Network and Access Control

Only the API gateway should remain publicly reachable. The worker VMs should stay
in private subnets with no public IPs. SSH should not be open to `0.0.0.0/0` in a
production environment; it should either be restricted to a known administrator
IP range or replaced with AWS Systems Manager Session Manager. Session Manager is
preferable because it removes inbound SSH exposure entirely and gives better
auditability.

The public endpoint should be moved behind an Application Load Balancer with
HTTPS listeners. TLS certificates can be managed with AWS Certificate Manager.
Nginx can still be used as an internal reverse proxy if needed, but TLS and
public routing are usually cleaner through ALB.

### Authentication, Abuse Protection, and API Safety

The current JSON endpoint has no authentication. I would add API keys or JWT
authentication before exposing it to real users. For simple service-to-service
access, an `X-API-Key` header validated at Nginx or the application layer is
enough. For user-facing access, AWS Cognito or another identity provider would
be more appropriate.

I would also add rate limiting and request size limits. LLM endpoints are easy
to abuse because a small request can trigger expensive compute. Nginx
`limit_req`, AWS WAF, and per-key quotas would reduce accidental or malicious
overload.

### Reliability and Health Checks

The system uses systemd to restart worker processes after crashes. For
production, I would add explicit health endpoints and alarms for each layer:

- API gateway/Nginx health
- caller VM iii engine health on ports `3111` and `49134`
- inference worker registration and model readiness

The EC2 instances should be placed in Auto Scaling Groups so failed instances are
replaced automatically. The API gateway should be behind an ALB health check so
bad instances can be removed from rotation.

### Logging, Metrics, and Tracing

Logs should be shipped to CloudWatch Logs using the CloudWatch agent or a
standard log collector. Useful alarms include:

- API `5xx` rate
- Nginx upstream failures
- iii service restarts
- CPU and memory pressure
- disk usage
- inference latency

Because the request crosses Nginx, a TypeScript worker, and a Python worker,
distributed tracing would be useful. The iii observability worker already gives
a starting point; in production I would export traces and metrics to a durable
backend rather than keeping them in memory.

### Secrets and State

No cloud credentials, SSH keys, Terraform state files, or `.tfvars` files should
be committed to Git. Terraform state should be moved to a remote encrypted S3
backend with DynamoDB locking. Secrets should be stored in AWS Secrets Manager or
SSM Parameter Store and injected at runtime.

EBS volumes should be encrypted, IMDSv2 should be required, and IAM roles should
follow least privilege. The EC2 instances in this assignment do not need broad
AWS permissions.

### Deployment Process

For a production version, I would avoid mutable bootstrapping directly from the
main branch. Better options are:

- bake AMIs with Packer,
- build Docker images and deploy them through ECS/EKS,
- pin package versions and iii versions,
- run Terraform in CI with reviewable plans,
- keep deployment artifacts immutable.

This would make rollbacks and reproducibility stronger than cloning the latest
GitHub branch during `user_data`.

## If the Model Were 100x Larger

A 100x larger model changes the design from a small CPU deployment to a GPU
serving problem.

### Compute

The inference VM would move from `t3.large` CPU to GPU instances such as AWS G5,
G6, P4, or P5 families depending on model size and latency targets. If the model
does not fit on one GPU, the serving layer would need tensor parallelism or
pipeline parallelism across multiple GPUs.

### Serving Runtime

Instead of loading the model directly with a simple Python worker, I would use a
model serving runtime optimized for LLMs, such as vLLM, TGI, TensorRT-LLM, or a
managed endpoint like SageMaker. These systems support batching, KV-cache
management, streaming responses, and higher GPU utilization.

### Model Storage

Large model weights should not be downloaded on every boot. I would store them
in S3 or EFS/FSx and cache them on local NVMe or EBS volumes. Startup should
verify checksums and reuse cached weights when possible.

### Queueing and Backpressure

For larger models, requests can take longer and cost more. I would introduce a
queue such as SQS between the API layer and inference workers for asynchronous
workloads. For synchronous chat, I would still add concurrency limits,
timeouts, and backpressure so the system fails predictably instead of
overloading GPU memory.

### Orchestration and Autoscaling

Raw EC2 with systemd is understandable for this assignment, but a larger model
would benefit from ECS or EKS. Containers make deployments repeatable, and GPU
scheduling/autoscaling is easier to manage through an orchestrator. Autoscaling
signals should include queue depth, GPU utilization, memory usage, and request
latency.

### Cost Controls

GPU instances are expensive. I would use:

- Savings Plans or Reserved Instances for baseline capacity,
- Spot Instances for batch jobs,
- scheduled scaling for predictable traffic,
- CloudWatch budgets and alarms,
- per-request cost tracking.

The main design change is that the inference tier becomes the cost and scaling
center of the system. The API gateway and caller worker can remain lightweight,
but the model serving layer needs specialized GPU infrastructure, caching,
batching, observability, and strict traffic control.
