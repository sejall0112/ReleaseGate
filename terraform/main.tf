terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Networking — reuse AWS's default VPC/subnet instead of creating our own.
# Every AWS account already has a default VPC with a public subnet and
# internet gateway attached, so for a single free-tier instance there's no
# need to build custom networking from scratch.
# ---------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "k3s_host" {
  name        = "${var.project_name}-k3s-sg"
  description = "Allow SSH, k3s API, and app traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "k3s API server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "NodePort range for app access"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sg" }
}

# ---------------------------------------------------------------------------
# EC2 host running k3s (free-tier eligible instance type)
# ---------------------------------------------------------------------------

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "k3s_host" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.k3s_host.id]
  key_name               = var.key_pair_name
  iam_instance_profile   = aws_iam_instance_profile.k3s_host.name

  user_data = <<-EOF
  #!/bin/bash
  set -e

  PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

  curl -sfL https://get.k3s.io -o /tmp/install-k3s.sh

  chmod +x /tmp/install-k3s.sh

  /tmp/install-k3s.sh server --tls-san $${PUBLIC_IP}
  EOF
}

# ---------------------------------------------------------------------------
# ECR repository — stores the ReleaseGate app image (promoted by retagging)
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "MUTABLE" # required so we can retag dev -> staging -> prod

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "${var.project_name}-ecr" }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 3 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 3
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# IAM — allows the k3s host to pull images from ECR
# ---------------------------------------------------------------------------

resource "aws_iam_role" "k3s_host" {
  name = "${var.project_name}-k3s-host-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  role       = aws_iam_role.k3s_host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "k3s_host" {
  name = "${var.project_name}-k3s-host-profile"
  role = aws_iam_role.k3s_host.name
}
