# ReleaseGate — Architecture Notes

## Design principle: build once, promote by reference

The single most important decision in this project is that the Docker image is **built exactly once per commit**, tagged with the Git SHA, and pushed to ECR. Every later stage (staging, prod) is a **retag of that same image**, not a rebuild.

This matters because rebuilding per-environment (e.g. `docker build` again for staging, again for prod) can silently produce a different image if:
- Base image tags aren't pinned (`python:3.12` today isn't the same bytes as `python:3.12` next week)
- Dependency resolution isn't fully locked
- Build-time environment variables change output

By promoting the same digest, ReleaseGate guarantees: **what passed staging is bit-for-bit what runs in prod.**

## Why a manual approval gate before prod

Automated health checks catch *known* failure modes (crash loops, failed readiness probes). They don't catch business-level judgment calls (e.g. "this is technically healthy but we're mid-incident on a dependent system, hold off"). The `input` step in the Jenkinsfile models this — a human is the final gate before production, even though every check before it is automated.

## Why namespaces instead of separate clusters

For a free-tier, single-EC2-instance k3s setup, running three separate clusters isn't realistic. Namespaces (`dev`, `staging`, `prod`) give logical isolation — separate Helm releases, separate resource quotas — without the cost of three clusters. In a funded/production context, this would typically become three separate clusters (or at minimum, staging and prod isolated from dev) for stronger blast-radius containment.

## Rollback mechanics

Each `helm upgrade --install` uses `--atomic`, which means: if the deployment doesn't reach a ready state within the timeout, Helm automatically rolls back to the previous release for that namespace. The `post { failure { ... } }` block in the Jenkinsfile is a second safety net that explicitly calls `helm rollback` for any environment that might have been left in a bad state.

## What's intentionally out of scope (v1)

- Multi-cluster / multi-region promotion
- Automated canary or blue-green traffic shifting (this is a straight rolling update per stage)
- Image signing / SBOM generation (would be a natural v2 addition alongside the health-check gates)
- GitOps controller (ArgoCD/Flux) — this version uses Jenkins to push changes directly; a v2 could have Jenkins only update a Git repo of manifests, with ArgoCD doing the actual apply
