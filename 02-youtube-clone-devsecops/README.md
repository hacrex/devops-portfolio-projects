# 2. YouTube Clone App with DevSecOps

## Overview
A second DevSecOps pipeline, deliberately different in tooling mix from Project 1 so you can speak to trade-offs between tools rather than repeating the same stack twice. This one leans on Snyk instead of OWASP Dependency-Check, and uses a self-managed Kubernetes cluster (kubeadm) instead of managed EKS, to prove you understand cluster bootstrapping too.

## Architecture
```
GitHub → GitHub Actions (CI)
   ├─ SonarQube (SAST)
   ├─ Snyk (SCA + container image scanning)
   ├─ Docker build & tag (commit SHA)
   ├─ Trivy (secondary image scan / filesystem scan)
   ├─ Push to DockerHub/ECR
   ▼
Self-managed Kubernetes cluster (kubeadm on EC2)
   ├─ Namespace isolation (dev/staging/prod namespaces)
   ├─ Deployment + Service + Ingress (NGINX Ingress Controller)
   ├─ RBAC (least-privilege service accounts)
   ├─ Resource Quotas + LimitRanges
   └─ Prometheus + Grafana + Alertmanager
```

## Pipeline Stages
1. **Checkout & lint** — code checkout plus a linter stage (ESLint/Pylint depending on stack).
2. **SAST** — SonarQube quality gate on pull requests, blocking merge on failure.
3. **SCA** — Snyk scans dependencies and open-source licenses; fails on high-severity findings.
4. **Build & tag** — Docker image tagged with git SHA + semantic version.
5. **Image scan** — Trivy filesystem + image scan as a second, independent scanner (defense in depth — don't rely on one scanner's database).
6. **Push to registry.**
7. **Deploy** — `kubectl apply` (or Helm upgrade) against the correct namespace based on branch (feature branch → dev, main → staging, tag → prod).
8. **Alerting** — Alertmanager routes critical alerts (pod crash loops, high error rate) to Slack/email.

## Tools Used
GitHub Actions, SonarQube, Snyk, Docker, Trivy, kubeadm-provisioned Kubernetes, NGINX Ingress, Helm, RBAC, Prometheus, Grafana, Alertmanager.

## What to Build & Push to This Folder
- `.github/workflows/ci-cd.yml`
- `Dockerfile`
- `helm/` chart (values per environment: `values-dev.yaml`, `values-staging.yaml`, `values-prod.yaml`)
- `k8s/rbac/` — ServiceAccount, Role, RoleBinding manifests
- `k8s/resource-quota.yaml`, `k8s/limit-range.yaml`
- `monitoring/alertmanager-config.yaml`
- Notes file `docs/cluster-bootstrap.md` documenting how you stood up kubeadm (init command, CNI choice, join commands) — this is your proof you didn't just use a managed service

## Interview Points

**What this project proves:** you can bootstrap and administer a Kubernetes cluster yourself (not just consume EKS/GKE), you understand namespace-based multi-environment isolation, and you know why using two different scanners in a pipeline is a deliberate defense-in-depth choice, not redundancy.

**Likely questions and how to answer them:**
- *"Why self-managed Kubernetes here when Project 1 used EKS?"* — To demonstrate you understand what a managed control plane actually abstracts away (etcd, API server HA, upgrades) versus what you have to handle yourself when self-managing (certificate rotation, etcd backups, node OS patching).
- *"Walk me through what CNI you chose and why."* — Name it (Calico/Flannel/Cilium) and give one concrete reason (e.g., Calico for NetworkPolicy support, Cilium for eBPF-based observability).
- *"Why run two image scanners (Snyk and Trivy)?"* — Different vulnerability databases and update cadences; a CVE disclosed today might be in one database before the other. In a real security-conscious org this is standard, not overkill — but be ready to also say when you'd *not* do this (e.g., if pipeline speed is the bottleneck and both tools show >95% overlap in findings).
- *"How do you isolate dev/staging/prod on the same cluster safely?"* — Namespaces + NetworkPolicies + RBAC + ResourceQuotas together, not namespaces alone (a common trap answer that shows shallow understanding).
- *"What does your RBAC actually restrict? Give a concrete example."* — Have one real example ready: e.g., the CI service account can only `create`/`update` Deployments and Services in its target namespace, not `delete` or touch other namespaces, and cannot read Secrets outside its own namespace.
- *"How do you back up etcd on a self-managed cluster, and have you tested restoring it?"* — Answer honestly. If you only took a snapshot and never restored it, say so and say why that's your acknowledged gap — that's a stronger answer than pretending you tested a full DR drill you didn't.

**Weak spots to pre-empt:** be ready to explain resource requests/limits you set and why (interviewers often probe this because it's where "I copied a YAML from a tutorial" candidates fall apart).

**Numbers/metrics to have ready:** cluster node count and instance sizes, number of pipeline runs, mean pipeline duration, percentage of findings caught by SAST vs SCA vs image scan (shows you actually looked at the outputs).
