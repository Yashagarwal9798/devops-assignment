# =============================================================================
# Security Groups — Firewall Rules
# =============================================================================
# Two security groups:
#   1. api_gateway — public-facing: allows HTTP (80) and SSH (22) from internet
#   2. workers — private: only allows traffic from within the VPC

# ---------------------------------------------------------------------------
# API Gateway Security Group
# ---------------------------------------------------------------------------
resource "aws_security_group" "api_gateway" {
  name        = "${var.project_name}-api-sg"
  description = "Allow HTTP from internet and SSH for management"
  vpc_id      = aws_vpc.main.id

  # HTTP from anywhere (this is the public API endpoint)
  ingress {
    description = "HTTP API access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH from anywhere (for initial setup — restrict in production)
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-api-sg"
    Project = var.project_name
  }
}

# ---------------------------------------------------------------------------
# Workers Security Group
# ---------------------------------------------------------------------------
resource "aws_security_group" "workers" {
  name        = "${var.project_name}-workers-sg"
  description = "Allow internal VPC traffic only - workers are not publicly accessible"
  vpc_id      = aws_vpc.main.id

  # Allow ALL traffic from within the VPC
  # Workers need to communicate via RPC (port 49134) and iii-http (port 3111)
  ingress {
    description = "All VPC internal traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow SSH from the API gateway security group (bastion hop)
  ingress {
    description     = "SSH from API gateway (bastion)"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.api_gateway.id]
  }

  # Allow all outbound (needed for package downloads via NAT)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-workers-sg"
    Project = var.project_name
  }
}
