# 8. 3-Tier Application DevSecOps CI/CD Pipeline

## Overview
A classic 3-tier architecture (presentation / application / data) deployed and secured end-to-end, with independent CI/CD pipelines per tier so you can speak to why coupling deployment cadence across tiers is a mistake, and how each tier has different security concerns.

## Architecture
```
Tier 1 — Presentation           Tier 2 — Application            Tier 3 — Data
(React/Static frontend)         (API service, e.g. Node/Java)   (RDS/PostgreSQL)
      │                                 │                              │
      ▼                                 ▼                              ▼
CI: lint, build,               CI: SAST (SonarQube),          IaC: Terraform manages
S3 + CloudFront deploy         SCA (Snyk), Docker build,       RDS instance, security
(or containerized + K8s)       Trivy scan, push to ECR         groups, subnet groups,
      │                                 │                       automated backups,
      ▼                                 ▼                       encryption at rest (KMS)
CD: invalidate CDN cache       CD: deploy to K8s (Deployment          │
                                + Service), Ingress routes             ▼
                                /api/* to this tier             Migration pipeline:
                                        │                       Flyway/Liquibase runs
                                        ▼                       schema migrations as a
                              WAF in front of Ingress           separate, gated CI job
                              (rate limiting, OWASP rules)
```

## Pipeline Stages (per tier, run independently)

**Tier 1 — Presentation:**
1. Lint + build (webpack/vite)
2. Lighthouse/accessibility check (optional but a good differentiator)
3. Deploy static assets to S3, invalidate CloudFront cache
4. Security: CSP headers configured on CloudFront, S3 bucket policy denies public write

**Tier 2 — Application:**
1. Unit tests + SAST (SonarQube)
2. SCA (Snyk) for dependency vulnerabilities
3. Docker build, Trivy image scan
4. Push to ECR, deploy to Kubernetes (rolling update)
5. WAF rules in front of the Ingress (rate limiting, SQL injection/XSS pattern blocking)

**Tier 3 — Data:**
1. Terraform manages RDS provisioning: private subnet only, security group allowing traffic only from the application tier's security group, encryption at rest via KMS, automated snapshots
2. Schema migrations run as a separate, explicitly gated CI job (Flyway/Liquibase) — never auto-applied on every app deploy, since a bad migration is much harder to roll back than a bad app deploy
3. Secrets (DB credentials) pulled from AWS Secrets Manager at runtime by the application tier, never embedded in app config files

## Tools Used
React/static frontend tooling, S3, CloudFront, Node.js/Java API, SonarQube, Snyk, Docker, Trivy, ECR, Kubernetes, NGINX Ingress + AWS WAF, Terraform, RDS/PostgreSQL, KMS, Flyway/Liquibase, AWS Secrets Manager.

## What to Build & Push to This Folder
- `presentation-tier/` — frontend app + its own CI workflow deploying to S3/CloudFront
- `application-tier/` — API service + its own CI/CD pipeline (SonarQube, Snyk, Trivy, K8s deploy)
- `data-tier/` — Terraform for RDS + `migrations/` folder with versioned SQL migration files + a separate migration pipeline definition
- `docs/network-diagram.md` — VPC layout showing which tier sits in which subnet, and exact security group rules between tiers (this is the artifact interviewers will ask you to draw on a whiteboard, so have it memorized, not just written down)
- `docs/waf-rules.md` — the actual WAF rules configured and what attack pattern each one addresses

## Interview Points

**What this project proves:** you understand that a real application isn't one deployable unit — different tiers have different release cadences, different security postures, and different blast radii when something goes wrong — and that IaC/CI discipline needs to reflect that.

**Likely questions and how to answer them:**
- *"Why separate pipelines per tier instead of one pipeline that deploys everything together?"* — Different tiers change at different rates (frontend changes daily, DB schema rarely) and have different risk profiles; coupling them means a trivial CSS fix requires the same review/approval rigor as a schema migration, which slows teams down and desensitizes reviewers to real risk.
- *"Why is schema migration a separate, gated job instead of part of the app deploy?"* — A bad app deploy rolls back cleanly (previous container image); a bad schema migration (e.g., a dropped column) can be destructive and may not have a clean automatic rollback — it needs its own review, its own gate, and ideally a tested down-migration before it ever runs in production.
- *"How is the data tier network-isolated from the internet?"* — RDS lives in private subnets with no route to an internet gateway; security group only allows inbound traffic on the DB port from the application tier's security group specifically (not a CIDR range) — be ready to say this exact detail, it's the single most common "did you actually configure this or just say 3-tier" check.
- *"What does the WAF actually block, concretely?"* — Name at least one real rule: rate-based rule limiting requests per IP per 5 minutes, and the AWS Managed Rule for OWASP Top 10 (SQLi/XSS pattern matching). Vague "it blocks bad traffic" answers signal you didn't configure it yourself.
- *"How do you handle a secret like a DB password across all three tiers without ever storing it in code?"* — Application tier fetches it from Secrets Manager at container startup (via IAM role, not a hardcoded key); Terraform generates/stores the initial password in Secrets Manager directly rather than writing it to a `.tfvars` file.
- *"If the application tier needs a new column added to a table, walk me through the full flow."* — Migration script written and reviewed → migration pipeline run (gated, likely against staging first) → application tier code that uses the new column deployed after the migration is confirmed successful, never before — sequencing matters and is a common trip-up question.

**Weak spots to pre-empt:** if your "3 tiers" are really just 3 folders in one repo deployed by one combined pipeline, be honest that the separation is logical/architectural in this portfolio version rather than fully independent CI/CD, and say what fully separating them (separate repos, separate deploy schedules) would require.

**Numbers/metrics to have ready:** deploy frequency you're simulating per tier, RDS backup retention period configured, WAF rule count, one concrete example of a schema migration you wrote and tested.
