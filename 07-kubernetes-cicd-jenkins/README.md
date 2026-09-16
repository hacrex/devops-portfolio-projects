# 7. Kubernetes CI/CD Using Jenkins

## Overview
Builds directly on Project 6: instead of deploying to a single EC2 via `docker run`, Jenkins now deploys to a Kubernetes cluster using Helm, with a defined rollback strategy and Jenkins itself potentially running as pods inside the cluster (Jenkins-on-Kubernetes) rather than a standalone VM.

## Architecture
```
GitHub webhook → Jenkins
                    │
                    ▼
          Build, test, SonarQube gate (same as Project 6)
                    │
                    ▼
          Docker build → push to ECR
                    │
                    ▼
          Jenkins Kubernetes plugin: dynamic agent pod spun up
          in-cluster to run `helm upgrade` against the target namespace
                    │
                    ▼
          Kubernetes cluster (EKS or self-managed)
             ├─ Helm release (versioned, rollback-capable)
             ├─ Readiness/liveness probes gate traffic cutover
             └─ `helm rollback` on failed health checks
```

## Pipeline Stages
1. **Trigger** — GitHub webhook fires Jenkins job (same mechanism as Project 6).
2. **Build, test, quality gate** — reuse the same SonarQube-gated stages.
3. **Containerize & push** — Docker build, push to ECR.
4. **Dynamic agent provisioning** — Jenkins Kubernetes plugin spins up an ephemeral agent pod inside the cluster for the deploy stage (proves you understand Jenkins-on-K8s, not just Jenkins-talks-to-K8s-from-outside).
5. **Helm upgrade** — `helm upgrade --install` with the new image tag, targeting the correct namespace based on branch.
6. **Health check gate** — Kubernetes readiness probes must pass before the rollout is considered complete; Jenkins waits on rollout status (`kubectl rollout status`).
7. **Automatic rollback** — if rollout status times out or fails, pipeline runs `helm rollback` to the last known-good release automatically.

## Tools Used
Jenkins (with Kubernetes plugin for dynamic agents), Docker, ECR, Kubernetes (EKS or self-managed), Helm, `kubectl`, readiness/liveness probes.

## What to Build & Push to This Folder
- `Jenkinsfile` using the `kubernetes` agent block (pod template defined in-pipeline or as a separate YAML)
- `helm-chart/` — your app's Helm chart: `Chart.yaml`, `values.yaml`, `templates/deployment.yaml`, `templates/service.yaml`, with readiness/liveness probes defined
- `jenkins-k8s/service-account.yaml` and `role.yaml` — the RBAC Jenkins' service account needs to deploy (least privilege, not cluster-admin)
- `docs/rollback-test.md` — proof you actually triggered a bad deploy on purpose and watched the automatic rollback work

## Interview Points

**What this project proves:** you understand Jenkins-on-Kubernetes architecture (ephemeral agents vs. static agents) and Helm-based release management with automated rollback — a meaningfully deeper claim than "Jenkins deploys to Kubernetes."

**Likely questions and how to answer them:**
- *"Why run Jenkins agents as pods inside the cluster instead of a fixed EC2 agent?"* — Ephemeral, on-demand agents mean you're not paying for idle build capacity, each build gets a clean environment (no state leakage between builds), and agent scaling matches build load automatically via the Kubernetes plugin.
- *"What RBAC permissions does the Jenkins service account actually have, and why not cluster-admin?"* — Least privilege: your ServiceAccount should be scoped to `create`/`update`/`get` on Deployments/Services/Pods in specific namespaces only — cluster-admin is a common shortcut in tutorials that's a real security smell in an interview if you can't explain why you avoided it.
- *"Walk me through what happens, step by step, when a deploy fails a health check."* — `kubectl rollout status` (or Helm's built-in wait) times out because pods aren't reaching Ready state → pipeline stage fails → triggers `helm rollback <release> <previous-revision>` → traffic continues being served by the previous, still-running ReplicaSet in the meantime (this is why rolling updates don't cause downtime even during a bad deploy, if configured correctly).
- *"Why Helm instead of raw `kubectl apply` manifests?"* — Versioned releases with built-in rollback (`helm rollback`), templating for per-environment values, and release history tracking — raw manifests give you none of that natively.
- *"What's the difference between a readiness probe and a liveness probe, and which one gates your rollout?"* — Readiness determines if a pod should receive traffic (gates rollout progression); liveness determines if a pod should be restarted (doesn't gate rollout, it's about self-healing). Getting this distinction right is a common Kubernetes fundamentals check.
- *"How did you actually test the rollback path — did you simulate a failure?"* — Point to `docs/rollback-test.md`; if you didn't test it, say what you'd do (deliberately push a bad image with a failing health check endpoint) rather than claiming untested behavior works.

**Weak spots to pre-empt:** if your rollback is manual (you ran `helm rollback` yourself after noticing the failure) rather than pipeline-automated, say that clearly — it's still a legitimate answer, just don't claim automation you didn't build.

**Numbers/metrics to have ready:** agent pod startup time (how long until a build agent is ready), deploy duration, rollout timeout threshold you configured, one real rollback event with cause and recovery time.
