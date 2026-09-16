# 3. GitLab CI/CD with Terraform — Infrastructure as Code

## Overview
This project is about proving infrastructure discipline, not app deployment. GitLab CI/CD pipelines provision, plan, and apply Terraform changes against AWS (or GCP) with remote state, locking, and environment separation — the actual day-to-day work of a platform/cloud engineer.

## Architecture
```
Merge Request opened in GitLab
      │
      ▼
GitLab CI pipeline
  ├─ Stage: validate  → terraform fmt -check, terraform validate
  ├─ Stage: plan       → terraform plan, output posted as MR comment
  ├─ Stage: security   → tfsec / Checkov scan of the Terraform code
  ├─ (manual gate: human approval on MR)
  ▼
  ├─ Stage: apply      → terraform apply (only on merge to main, restricted runner)
  ▼
Remote backend: S3 + DynamoDB (state file + state locking)
      │
      ▼
Provisioned AWS infra: VPC, subnets, IAM roles, EKS/EC2, RDS, security groups
```

## Pipeline Stages
1. **Validate** — `terraform fmt -check` and `terraform validate` catch syntax/style issues immediately.
2. **Plan** — `terraform plan` output is posted back to the merge request so reviewers see the exact diff of infra changes before approving code.
3. **Security scan** — tfsec or Checkov scans the HCL itself for misconfigurations (e.g., open security groups, unencrypted S3 buckets, public RDS instances) before anything is applied.
4. **Manual approval gate** — apply stage requires a human click in GitLab, never auto-applies to production.
5. **Apply** — runs only on the protected `main` branch, using a restricted GitLab Runner with scoped IAM credentials.
6. **State management** — S3 backend for state storage, DynamoDB table for state locking to prevent concurrent applies from corrupting state.

## Tools Used
GitLab CI/CD, Terraform, tfsec/Checkov, AWS (S3, DynamoDB, VPC, IAM, EC2/EKS, RDS), GitLab protected branches/environments.

## What to Build & Push to This Folder
- `.gitlab-ci.yml` with the stages above
- `terraform/` — modularized: `modules/vpc/`, `modules/iam/`, `modules/compute/`, root `main.tf`/`variables.tf`/`outputs.tf`
- `terraform/backend.tf` showing the S3+DynamoDB remote backend config
- `environments/dev.tfvars`, `environments/prod.tfvars` — proving environment separation via variable files, not copy-pasted code
- `docs/state-recovery.md` — a short doc explaining what you'd do if the state file got corrupted or someone ran `terraform apply` locally and drifted from CI state

## Interview Points

**What this project proves:** you understand IaC as a discipline with real failure modes (state corruption, drift, concurrent applies) — not just "I wrote some `.tf` files that worked once."

**Likely questions and how to answer them:**
- *"Why remote state instead of local state?"* — Local state means only one person/machine has the source of truth, no locking, high risk of corruption or conflicting applies in a team setting. Remote state (S3) + locking (DynamoDB) makes state shared, versioned (via S3 versioning), and safe for concurrent CI runs.
- *"What happens if two pipelines try to apply at the same time?"* — DynamoDB lock causes the second `apply` to fail/wait rather than corrupt state — explain you tested this or at least understand the mechanism.
- *"How do you handle secrets in Terraform (e.g., DB passwords)?"* — Never in `.tfvars` committed to git. Name your actual approach: `TF_VAR_` environment variables injected from GitLab CI/CD variables (masked/protected), or pulling from AWS Secrets Manager/SSM Parameter Store via data sources.
- *"Someone manually changed a security group in the AWS console. What happens on the next pipeline run?"* — `terraform plan` will detect drift and show it wants to revert the manual change. Explain the org policy you'd want here: no console changes allowed, `terraform import` for anything created out-of-band.
- *"Why a manual approval gate on apply instead of full automation?"* — Infra changes (especially deletions/replacements) can be destructive and hard to undo (e.g., RDS instance replacement); a human review of the plan output before apply is a standard safety control, especially early in a team's IaC maturity.
- *"How is your Terraform code structured, and why modules?"* — Modules let you reuse VPC/IAM/compute patterns across dev/staging/prod without copy-pasting, and version them independently.

**Weak spots to pre-empt:** if you didn't test a real disaster scenario (corrupted state, failed apply mid-way), say what you'd do based on Terraform's documented behavior rather than pretending you've lived through it.

**Numbers/metrics to have ready:** number of resources managed, plan/apply runtime, how many environments, how many modules, one real "plan caught something before it broke prod" anecdote if you have one.
