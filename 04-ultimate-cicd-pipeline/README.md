# 4. THE Ultimate CI/CD Pipeline (Capstone)

## Overview
This is the capstone project — the one meant to answer "walk me through the most complete pipeline you've built" in a single, coherent story. It combines everything from the other 7 projects into one multi-environment pipeline: build → test → security → artifact → deploy to dev → integration test → promote to staging → manual gate → promote to prod → rollback plan.

## Architecture
```
Push to feature branch
      │
      ▼
CI: build, unit test, SAST (SonarQube), SCA (Snyk), Docker build, image scan (Trivy)
      │
      ▼
Push image to registry (tagged with commit SHA + semver)
      │
      ▼
CD → Dev environment (auto-deploy on every merge to develop)
      │  └─ Integration tests run against dev
      ▼
CD → Staging environment (auto-deploy on merge to main)
      │  └─ Smoke tests + performance/load test (k6 or JMeter)
      │  └─ Manual approval gate
      ▼
CD → Production (blue-green or canary deployment)
      │  └─ Health checks + automated rollback on failure threshold
      ▼
Post-deploy: monitoring dashboards + alerting confirm stability
```

## Pipeline Stages
1. **Build & unit test** — fail fast on broken code before any infra involvement.
2. **Static analysis + dependency scan** — SonarQube + Snyk quality gates.
3. **Containerize & scan** — Docker build, Trivy scan, fail on critical CVEs.
4. **Artifact versioning** — every image tagged with commit SHA and semantic version; artifacts are immutable once pushed.
5. **Deploy to Dev** — fully automatic on every merge to `develop`.
6. **Integration tests** — run against the live dev deployment (not mocks) to catch environment-specific issues.
7. **Deploy to Staging** — automatic on merge to `main`, followed by smoke tests and a load test.
8. **Manual approval gate** — a named human approves the promotion to production, with the staging test results attached.
9. **Deploy to Production** — blue-green (two full environments, instant traffic switch) or canary (gradual traffic shift, e.g., 10% → 50% → 100%) — pick one and justify it.
10. **Automated rollback** — if error rate or latency crosses a threshold post-deploy, the pipeline (or a tool like Argo Rollouts / Flagger) automatically reverts traffic to the previous version.
11. **Post-deploy verification** — dashboards and alerts confirm the new version is healthy before the pipeline is marked fully successful.

## Tools Used
GitHub Actions or Jenkins (pick one as primary orchestrator), SonarQube, Snyk, Docker, Trivy, Kubernetes, Argo Rollouts or Flagger (progressive delivery), k6/JMeter (load testing), Prometheus/Grafana, Slack/email notifications.

## What to Build & Push to This Folder
- Pipeline definition file (`Jenkinsfile` or `.github/workflows/pipeline.yml`) with all stages, using environment-specific jobs/stages
- `k8s/` manifests per environment (`dev/`, `staging/`, `prod/`) or a single Helm chart with per-env values files
- `progressive-delivery/` — Argo Rollouts `Rollout` CRD or Flagger `Canary` CRD manifest with your chosen strategy and thresholds
- `load-tests/` — a k6 or JMeter script actually run against staging, with results saved in `docs/load-test-results.md`
- `docs/pipeline-diagram.png` — a diagram of the full flow (this is the single most useful artifact for interviews — draw it, don't just describe it)
- `docs/rollback-runbook.md` — the exact steps (automated and manual) to roll back a bad production deploy

## Interview Points

**What this project proves:** you can design a full software delivery lifecycle, not just wire together tools — this is the project that most directly answers "have you owned a pipeline end-to-end?"

**Likely questions and how to answer them:**
- *"Why blue-green over canary, or vice versa?"* — Blue-green: instant rollback (just switch traffic back), but you pay for double infrastructure and it's all-or-nothing. Canary: cheaper, catches issues on a small percentage of real traffic before full rollout, but requires good metrics/automation to detect problems and is slower to reach 100%. Pick one for this project and be able to argue the trade-off, don't just say "canary is more modern."
- *"What exact metric triggers your automated rollback, and what's the threshold?"* — Have a specific number ready: e.g., HTTP 5xx rate above 2% over a 5-minute window, or p99 latency above a defined SLO. Vague answers ("if something looks wrong") signal you didn't actually implement this.
- *"Why a manual gate between staging and prod but not between dev and staging?"* — Risk asymmetry: dev deploys are cheap to be wrong about and self-correct fast via iteration; production deploys affect real users/revenue, so a human checkpoint with staging evidence attached is a deliberate, justified slowdown.
- *"How do you prevent secrets from leaking across environments?"* — Separate secret stores/namespaces per environment (e.g., separate AWS Secrets Manager paths or separate K8s namespaces with distinct RBAC), never a single shared secret reused across dev/staging/prod.
- *"What's the single biggest failure mode of a pipeline like this, and how did you mitigate it?"* — Good candidate answers: pipeline becoming a single point of failure (mitigate: keep manual `kubectl`/`helm` fallback documented), or flaky integration tests blocking every deploy (mitigate: quarantine flaky tests, track flakiness rate).
- *"How long does a full run take, dev to prod?"* — Have a real number. If it's slow, be ready to say what the bottleneck is and how you'd address it (parallelize test stages, cache dependencies, etc.).

**Weak spots to pre-empt:** if your "automated rollback" is actually a manual step you'd trigger yourself, say that plainly — claiming full automation on a capstone project and then not being able to explain the trigger logic is the fastest way to lose credibility in an interview.

**Numbers/metrics to have ready:** total pipeline duration end-to-end, deployment frequency you're simulating, MTTR (mean time to recovery) from your rollback runbook, load test results (requests/sec, p95/p99 latency at target load).
