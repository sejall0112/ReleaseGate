variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix used for tagging all resources"
  type        = string
  default     = "releasegate"
}

variable "instance_type" {
  description = "EC2 instance type for the k3s host (keep this free-tier eligible)"
  type        = string
  default     = "t3.small"
}

variable "key_pair_name" {
  description = "Name of an existing EC2 key pair used to SSH into the k3s host"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into the k3s host — restrict this to your own IP in production use"
  type        = string
  default     = "0.0.0.0/0"
}

variable "ecr_repo_name" {
  description = "Name of the ECR repository storing the ReleaseGate app image"
  type        = string
  default     = "releasegate-app"
}
