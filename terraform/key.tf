# =============================================================================
# SSH Key Pair
# =============================================================================
# Generates an SSH key pair so we can access the VMs.
# The private key is saved locally (NEVER commit it to git).

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "deployer" {
  key_name   = var.key_name
  public_key = tls_private_key.ssh.public_key_openssh
}

# Save the private key to a local file for SSH access
resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/devops-key.pem"
  file_permission = "0400"
}
