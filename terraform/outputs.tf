output "k3s_host_public_ip" {
  description = "Public IP of the EC2 instance running k3s"
  value       = aws_instance.k3s_host.public_ip
}

output "ecr_repository_url" {
  description = "URL of the ECR repository — used by Jenkins to push/retag images"
  value       = aws_ecr_repository.app.repository_url
}

output "fetch_kubeconfig_command" {
  description = "Run this to copy the k3s kubeconfig to your local machine, then edit the server IP"
  value       = "scp -i <your-key>.pem ubuntu@${aws_instance.k3s_host.public_ip}:/etc/rancher/k3s/k3s.yaml ./k3s-kubeconfig.yaml"
}

output "next_steps" {
  description = "Reminder"
  value       = "After copying kubeconfig, replace 'https://127.0.0.1:6443' with 'https://${aws_instance.k3s_host.public_ip}:6443' inside k3s-kubeconfig.yaml"
}
