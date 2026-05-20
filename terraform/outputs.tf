# =============================================================================
# Outputs — Important values printed after deployment
# =============================================================================

output "api_gateway_public_ip" {
  description = "Public IP of the API gateway — use this for curl requests"
  value       = aws_instance.api_gateway.public_ip
}

output "api_endpoint" {
  description = "Full API endpoint URL"
  value       = "http://${aws_instance.api_gateway.public_ip}/v1/chat/completions"
}

output "inference_worker_private_ip" {
  description = "Private IP of the inference worker (not accessible from internet)"
  value       = aws_instance.inference_worker.private_ip
}

output "caller_worker_private_ip" {
  description = "Private IP of the caller worker (not accessible from internet)"
  value       = aws_instance.caller_worker.private_ip
}

output "ssh_to_api_gateway" {
  description = "SSH command to connect to the API gateway (bastion host)"
  value       = "ssh -i terraform/devops-key.pem ubuntu@${aws_instance.api_gateway.public_ip}"
}

output "ssh_to_inference_worker" {
  description = "SSH to inference worker (hop through API gateway first)"
  value       = "ssh -i devops-key.pem -o ProxyJump=ubuntu@${aws_instance.api_gateway.public_ip} ubuntu@${aws_instance.inference_worker.private_ip}"
}

output "ssh_to_caller_worker" {
  description = "SSH to caller worker (hop through API gateway first)"
  value       = "ssh -i devops-key.pem -o ProxyJump=ubuntu@${aws_instance.api_gateway.public_ip} ubuntu@${aws_instance.caller_worker.private_ip}"
}

output "test_curl_command" {
  description = "Test the API with this curl command"
  value       = <<-EOT
    curl -X POST http://${aws_instance.api_gateway.public_ip}/v1/chat/completions \
      -H "Content-Type: application/json" \
      -d '{"messages": [{"role": "user", "content": "What is 2+2?"}]}'
  EOT
}
