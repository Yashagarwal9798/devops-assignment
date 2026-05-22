# =============================================================================
# EC2 Instances — The 3 Virtual Machines
# =============================================================================
# VM 1: inference-worker (Python) — Private Subnet, t3.large (8GB RAM)
# VM 2: caller-worker (TypeScript) — Private Subnet, t3.micro
# VM 3: api-gateway (Nginx reverse proxy) — Public Subnet, t3.micro

# ---------------------------------------------------------------------------
# Data source: Latest Ubuntu 22.04 AMI
# ---------------------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (official Ubuntu publisher)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------------------------------------------------------------------
# VM 1: Inference Worker (Python) — Private Subnet
# ---------------------------------------------------------------------------
resource "aws_instance" "inference_worker" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.inference_instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.workers.id]
  key_name               = aws_key_pair.deployer.key_name

  # Root volume — need space for model download (~500MB) + dependencies
  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/userdata/setup-inference-worker.sh", {
    github_repo_url          = "https://github.com/Yashagarwal9798/devops-assignment.git"
    caller_worker_private_ip = aws_instance.caller_worker.private_ip
  })
  user_data_replace_on_change = true

  depends_on = [aws_route_table_association.private]

  tags = {
    Name    = "${var.project_name}-inference-worker"
    Role    = "inference-worker"
    Project = var.project_name
  }
}

# ---------------------------------------------------------------------------
# VM 2: Caller Worker (TypeScript) — Private Subnet
# ---------------------------------------------------------------------------
resource "aws_instance" "caller_worker" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.caller_instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.workers.id]
  key_name               = aws_key_pair.deployer.key_name

  root_block_device {
    volume_size = 10
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/userdata/setup-caller-worker.sh", {
    github_repo_url = "https://github.com/Yashagarwal9798/devops-assignment.git"
  })
  user_data_replace_on_change = true

  depends_on = [aws_route_table_association.private]

  tags = {
    Name    = "${var.project_name}-caller-worker"
    Role    = "caller-worker"
    Project = var.project_name
  }
}

# ---------------------------------------------------------------------------
# VM 3: API Gateway (Nginx) — Public Subnet
# ---------------------------------------------------------------------------
resource "aws_instance" "api_gateway" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.api_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.api_gateway.id]
  key_name                    = aws_key_pair.deployer.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size = 10
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/userdata/setup-api-gateway.sh", {
    caller_worker_private_ip = aws_instance.caller_worker.private_ip
  })
  user_data_replace_on_change = true

  tags = {
    Name    = "${var.project_name}-api-gateway"
    Role    = "api-gateway"
    Project = var.project_name
  }
}
