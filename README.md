# DevOps / DevSecOps Portfolio — 8 End-to-End Projects

This repo is a single portfolio containing 8 independent, production-style DevOps/DevSecOps projects. Each project lives in its own folder with its own README covering architecture, pipeline stages, tools used, and — critically — an **Interview Points** section so you can defend the project in a technical interview, not just show a diagram.

None of these are "hello world" tutorials. Each one maps to a real hiring pattern: a recruiter or panel sees "Kubernetes + DevSecOps" or "Terraform IaC on GitLab" on a resume and probes for depth. The Interview Points sections exist to make sure you have that depth ready.

## How to use this repo

1. Pick 2–3 projects that best match the role you're targeting (don't try to be equally deep in all 8 — depth on 3 beats shallow breadth on 8).
2. Actually build and deploy each one you claim — screenshots, pipeline run logs, and a live (even if torn-down-after) URL matter more than the code itself.
3. Read every "Interview Points" section before an interview touching that project. They're organized as: **What it proves**, **Likely questions**, **Weak spots to pre-empt**, **Numbers/metrics to have ready**.
4. Keep each folder's pipeline config (Jenkinsfile / .gitlab-ci.yml / GitHub Actions workflow) actually runnable — a broken pipeline in your own portfolio repo is worse than not having the repo.
5. **Each project has a `DEPLOY.md` with step-by-step deployment instructions.** Start with `DEPLOY-ALL.md` for shared prerequisites and the recommended build order.

## Project index

| # | Folder | Project | Core skill proven |
|---|--------|---------|--------------------|
| 1 | `01-netflix-clone-k8s-devsecops/` | Netflix Clone on Kubernetes (Full DevSecOps) | Container security scanning + K8s deployment + monitoring |
| 2 | `02-youtube-clone-devsecops/` | YouTube Clone with DevSecOps | SAST/DAST/SCA integrated into CI, GitOps delivery |
| 3 | `03-gitlab-cicd-terraform-iac/` | GitLab CI/CD with Terraform | Infrastructure as Code, remote state, drift management |
| 4 | `04-ultimate-cicd-pipeline/` | "The Ultimate CI/CD Pipeline" | Multi-stage, multi-environment pipeline design end-to-end |
| 5 | `05-realtime-devops-cicd/` | Real-Time DevOps CI/CD Project | Event-driven / webhook-triggered continuous delivery |
| 6 | `06-jenkins-sonarqube-docker-aws/` | Jenkins + SonarQube + Docker + GitHub Webhooks on AWS | Classic self-hosted CI toolchain, quality gates |
| 7 | `07-kubernetes-cicd-jenkins/` | Kubernetes CI/CD using Jenkins | Jenkins-driven K8s deployments, Helm, rollback strategy |
| 8 | `08-3tier-devsecops-cicd/` | 3-Tier Application DevSecOps CI/CD | Full-stack architecture security across all 3 tiers |

## Suggested build order (if starting from zero)

Build in this order so each project reuses skills/infra from the previous one instead of starting cold every time:

1. **#6** (Jenkins + SonarQube + Docker on AWS) — establishes your CI toolchain fundamentals on a single VM.
2. **#3** (GitLab + Terraform) — adds IaC discipline; you'll provision the infra instead of clicking in the console.
3. **#7** (K8s CI/CD with Jenkins) — moves your deployment target from a single Docker host to a cluster.
4. **#1** and **#2** (Netflix/YouTube clone DevSecOps) — layer in the full security scanning stack (SAST/DAST/SCA/image scanning) on top of what you already built.
5. **#8** (3-tier DevSecOps) — combine everything into one architecture spanning presentation/app/data tiers.
6. **#5** (Real-time DevOps) — add webhook/event-driven triggers and near-zero-touch delivery.
7. **#4** (Ultimate CI/CD) — your capstone: multi-environment (dev/staging/prod), approval gates, rollback, the works.

## Cross-cutting interview theme

Across all 8 projects, be ready to answer this framing question, because it separates candidates who followed a tutorial from candidates who understand DevOps:

> "Before you touched any CI/CD tool, what did you decide about networking, security, storage, and disaster recovery for this environment?"

Interviewers who ask this are checking whether you understand that **tooling sits on top of infrastructure decisions**, not the other way around — VPC/subnet design, IAM least-privilege, secrets management, backup/restore strategy, and state file security should all be decisions you made *before* writing a single pipeline stage. Have one sentence ready per project on this.

## Repo structure

```
devops-portfolio/
├── README.md
├── LICENSE
├── .gitignore
├── 01-netflix-clone-k8s-devsecops/
│   ├── README.md
│   ├── Dockerfile
│   ├── .github/workflows/ci.yml
│   ├── k8s/ (deployment, service, ingress, hpa, networkpolicy)
│   ├── argocd/application.yaml
│   └── monitoring/ (prometheus-config, grafana-dashboard)
├── 02-youtube-clone-devsecops/
│   ├── README.md
│   ├── Dockerfile
│   ├── .github/workflows/ci-cd.yml
│   ├── helm/ (Chart.yaml, values, templates)
│   ├── k8s/rbac/ (service-account, role, role-binding)
│   ├── k8s/ (resource-quota, limit-range)
│   ├── monitoring/alertmanager-config.yaml
│   └── docs/cluster-bootstrap.md
├── 03-gitlab-cicd-terraform-iac/
│   ├── README.md
│   ├── .gitlab-ci.yml
│   ├── terraform/ (modules: vpc, iam, compute)
│   ├── environments/ (dev.tfvars, prod.tfvars)
│   ├── backends/ (dev.hcl, prod.hcl)
│   └── docs/state-recovery.md
├── 04-ultimate-cicd-pipeline/
│   ├── README.md
│   ├── .github/workflows/pipeline.yml
│   ├── k8s/ (dev/, staging/, prod/)
│   ├── progressive-delivery/canary.yaml
│   ├── load-tests/load-test.js
│   └── docs/rollback-runbook.md
├── 05-realtime-devops-cicd/
│   ├── README.md
│   ├── Jenkinsfile
│   ├── webhook-config/setup.md
│   ├── scripts/verify-webhook-signature.sh
│   ├── notifications/slack-notify.sh
│   └── docs/trigger-latency.md
├── 06-jenkins-sonarqube-docker-aws/
│   ├── README.md
│   ├── Jenkinsfile
│   ├── Dockerfile
│   ├── app/ (Spring Boot application)
│   ├── infra/ (ec2-setup, sonarqube-setup)
│   └── docs/jenkins-credentials.md
├── 07-kubernetes-cicd-jenkins/
│   ├── README.md
│   ├── Jenkinsfile
│   ├── helm-chart/ (Chart.yaml, values, templates)
│   ├── jenkins-k8s/ (service-account, role, role-binding)
│   └── docs/rollback-test.md
└── 08-3tier-devsecops-cicd/
    ├── README.md
    ├── presentation-tier/ (Dockerfile, nginx.conf, CI workflow)
    ├── application-tier/ (Dockerfile, K8s manifests, CI/CD workflow)
    ├── data-tier/ (Terraform for RDS, SQL migrations, migration pipeline)
    └── docs/ (network-diagram, waf-rules)
```

Each project README follows the same template: **Overview → Architecture → Pipeline Stages → Tools Used → What to Build & Push to This Folder → Interview Points**.
