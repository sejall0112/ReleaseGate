# ReleaseGate

**An automated environment promotion pipeline that enforces safe, auditable progression of container images from dev → staging → production.**

Built with Terraform, Jenkins, Docker, Amazon ECR, Helm, and k3s.

---

## The Problem

Most CI/CD demos show code going from a commit straight to a running deployment. That's the easy part. The harder, more realistic problem is: **how do you make sure only a validated, unchanged artifact reaches production** — without rebuilding it (and risking a different result), and without a human having to manually track which image is safe to promote?

ReleaseGate answers that. It builds a container image **exactly once**, then promotes that same image (by digest, not by rebuild) through dev → staging → production, gated by automated health checks at each stage. Nothing reaches prod without proving itself in the stage before it.

## What It Actually Does

1. **Terraform** provisions the underlying infrastructure — a VPC, a free-tier EC2 instance running k3s (lightweight Kubernetes), an ECR repository, and the IAM roles needed to pull images securely.
2. **Jenkins** builds a Docker image once per commit, tags it with the Git SHA, and pushes it to ECR.
3. The pipeline deploys that image to **dev** via Helm.
4. An automated health check runs against dev. If it passes, Jenkins **retags the same image digest** as `staging` in ECR — no rebuild — and deploys to staging via Helm.
5. The health check runs again. If it passes, the pipeline requires an **approval gate** (manual click, simulating a real release manager sign-off) before retagging the same digest as `prod` and deploying.
6. If a health check fails at any stage, the pipeline halts and Helm rolls back to the last known-good release (`helm rollback`), and the promotion never reaches the next stage.

## Architecture

```
                  ┌─────────────────────────────────────────────┐
                  │                 Jenkins                     │
                  │                                              │
   git push  ───▶ │  1. Build Docker image                       │
                  │  2. Push to ECR  (tag: <git-sha>)            │
                  │  3. helm upgrade --install  →  DEV            │
                  │  4. Run health check  ───┐                    │
                  │                          ▼                    │
                  │              pass? ──▶ retag image as staging │
                  │  5. helm upgrade --install  →  STAGING        │
                  │  6. Run health check  ───┐                    │
                  │                          ▼                    │
                  │              pass? ──▶ [ manual approval ]    │
                  │  7. retag image as prod                       │
                  │  8. helm upgrade --install  →  PROD            │
                  │                                              │
                  │  any failure → helm rollback, pipeline stops  │
                  └─────────────────────────────────────────────┘
                            │                    │
                            ▼                    ▼
                    ┌───────────────┐    ┌───────────────┐
                    │   Amazon ECR   │    │  k3s cluster   │
                    │  (image store, │    │ (dev/staging/  │
                    │   3 tags per   │    │  prod          │
                    │   digest)      │    │  namespaces)   │
                    └───────────────┘    └───────────────┘

     Infra layer (VPC, EC2, IAM, ECR) provisioned by Terraform
```

## Why This Matters (the storyline)

Imagine joining a team where deployments are already automated, but nobody can answer: *"Is the image running in prod the exact same one that was tested in staging?"* or *"If this deploy breaks something, how fast can we get back to the last good version?"*

ReleaseGate is built to answer both questions with certainty:
- **Immutability** — the image running in prod is provably the same bytes that passed staging, because it was never rebuilt.
- **Auditability** — every promotion is a Jenkins pipeline run with a timestamp, approver, and image digest logged.
- **Fast recovery** — `helm rollback` reverts to the previous release in seconds, not a fresh deploy.

## Repo Structure

```
ReleaseGate/
├── terraform/            # VPC, EC2 (k3s host), ECR repo, IAM roles
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── app/                   # Sample containerized app
│   └── Dockerfile
├── helm-chart/            # Single chart, reused across all 3 environments
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values-dev.yaml
│   ├── values-staging.yaml
│   ├── values-prod.yaml
│   └── templates/
├── jenkins/
│   └── Jenkinsfile        # Build → dev → healthcheck → staging → healthcheck → approval → prod
└── docs/
    └── architecture.md
```

## Getting Started

```bash
# 1. Provision infrastructure
cd terraform
terraform init
terraform apply

# 2. Point kubectl at the k3s cluster (Terraform output gives you the command)
export KUBECONFIG=./k3s-kubeconfig.yaml

# 3. Point Jenkins at this repo and run the pipeline
#    (Jenkinsfile lives at jenkins/Jenkinsfile)

# 4. Tear down when done to avoid any charges
cd terraform
terraform destroy
```

## Cost

Designed to run entirely on the AWS Free Tier: one `t3.micro`/`t2.micro` EC2 instance running k3s, and ECR (free for the first 500MB/month). No EKS, no NAT Gateway, no Load Balancer by default. Always run `terraform destroy` after each session.

## Tech Stack

`Terraform` · `Jenkins` · `Docker` · `Amazon ECR` · `Helm` · `Kubernetes (k3s)`
