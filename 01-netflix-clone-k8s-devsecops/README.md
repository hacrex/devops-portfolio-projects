# 1. Netflix Clone on Kubernetes — Full DevSecOps

## Overview
A containerized Netflix-clone web app deployed to Kubernetes through a pipeline that enforces security at every stage: source code, dependencies, container image, and running cluster. The point of this project is not the clone app — it's proving you can build a "shift-left" security pipeline around any application.

## Architecture
```
Developer push → GitHub
      │
      ▼
Jenkins (or GitHub Actions) CI
  ├─ SonarQube (SAST — code quality & vulnerabilities)
  ├─ OWASP Dependency-Check / Snyk (SCA — vulnerable dependencies)
  ├─ Docker build
  ├─ Trivy (image scan — CVEs in base image + layers)
  ├─ Push to ECR/DockerHub (only if scans pass quality gate)
  ▼
ArgoCD (GitOps) → pulls manifest changes → deploys to EKS
      │
      ▼
Kubernetes cluster (EKS)
  ├─ Deployment + Service + Ingress
  ├─ Horizontal Pod Autoscaler
  ├─ Network Policies (restrict pod-to-pod traffic)
  └─ Prometheus + Grafana (monitoring) / Falco (runtime security)
```

## Pipeline Stages
1. **Checkout** — pull source from GitHub.
2. **Static Code Analysis** — SonarQube quality gate; pipeline fails below threshold.
3. **Dependency Scanning (SCA)** — OWASP Dependency-Check or Snyk against `package.json`/`requirements.txt`.
4. **Build** — Docker image build, tagged with commit SHA (never `latest` in a real pipeline).
5. **Image Scanning** — Trivy scans the built image for OS and library CVEs; fail on CRITICAL/HIGH.
6. **Push** — image pushed to ECR/DockerHub registry only after all gates pass.
7. **Deploy (GitOps)** — ArgoCD watches a manifests repo; a bump to the image tag triggers automatic sync to EKS.
8. **Runtime Security & Monitoring** — Falco watches for anomalous syscalls in running containers; Prometheus/Grafana track pod health, resource usage, and app metrics.

## Tools Used
Jenkins/GitHub Actions, SonarQube, OWASP Dependency-Check or Snyk, Docker, Trivy, Amazon EKS, ArgoCD, Prometheus, Grafana, Falco, Kubernetes NetworkPolicies.

## What to Build & Push to This Folder
- `Dockerfile` (multi-stage, non-root user, pinned base image tag — not `:latest`)
- `Jenkinsfile` or `.github/workflows/ci.yml` with all pipeline stages above
- `k8s/` manifests: `deployment.yaml`, `service.yaml`, `ingress.yaml`, `hpa.yaml`, `networkpolicy.yaml`
- `argocd/application.yaml`
- `monitoring/` — Prometheus scrape config + a Grafana dashboard JSON export
- Screenshots: SonarQube dashboard, Trivy scan output, ArgoCD sync screen, Grafana dashboard — put these in `docs/screenshots/`

## Interview Points

**What this project proves:** you understand shift-left security (catching problems before deploy, not after), GitOps deployment patterns, and basic K8s hardening — not just "I ran `kubectl apply`."

**Likely questions and how to answer them:**
- *"Why Trivy and not just relying on SonarQube?"* — SonarQube analyzes your source code (SAST); it has no visibility into the OS packages and libraries baked into your container's base image. Trivy scans the actual image layers for known CVEs. You need both because they cover different attack surfaces.
- *"What happens if a HIGH vulnerability is found in the base image and there's no patched image tag yet?"* — Explain your fallback: pin to a distroless or slim variant, add a documented exception with a re-scan reminder, or switch base images. Never say "we just ignored it."
- *"Why ArgoCD instead of `kubectl apply` from Jenkins?"* — GitOps means the cluster state is declarative and pulled, not pushed; the manifests repo is your source of truth, drift is automatically corrected, and you get an audit trail of every deployed change via git history.
- *"How do you handle secrets in this pipeline?"* — Never hardcoded in manifests. Name the specific approach you used: Kubernetes Secrets + Sealed Secrets/External Secrets Operator, or AWS Secrets Manager pulled at runtime.
- *"What's your rollback strategy if the new version crashes in production?"* — ArgoCD lets you roll back to a previous synced revision in one click/command; also mention `kubectl rollout undo` as the imperative fallback and why GitOps rollback is preferable (it's auditable).
- *"How does the Horizontal Pod Autoscaler decide to scale, and what metric did you use?"* — Be specific: CPU utilization target percentage, or a custom metric via Prometheus Adapter if you went further.

**Weak spots to pre-empt:** if you didn't actually configure NetworkPolicies or Falco, don't claim "full DevSecOps" — say what you built and name what you'd add next (this is a stronger interview answer than overclaiming and getting caught).

**Numbers/metrics to have ready:** image size before/after using a slim base image, scan duration, number of CVEs caught and remediated, pipeline total runtime.
