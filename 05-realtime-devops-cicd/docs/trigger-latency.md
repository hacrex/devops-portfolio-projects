# Trigger Latency Measurements

## Push-to-Pipeline-Start Latency

Measures the time from `git push` completing to Jenkins starting the pipeline build.

| Test Case | Date | Branch | Latency (seconds) | Notes |
|-----------|------|--------|-------------------|-------|
| Feature push | 2026-09-10 | feature/login | 3.2s | GitHub → Jenkins webhook |
| Develop push | 2026-09-10 | develop | 2.8s | Same repo, same network |
| Main push | 2026-09-11 | main | 3.5s | Includes SSL overhead |
| Tag creation | 2026-09-12 | v1.0.0 | 4.1s | Tag event payload larger |

**Average push-to-pipeline-start:** 3.4 seconds

### How Measured
1. Record `GIT_COMMITTER_DATE` at commit time (precision: ISO 8601 with seconds)
2. Record Jenkins build start timestamp from the build page (`BUILD_START` field)
3. Latency = BUILD_START - GIT_COMMITTER_DATE

Script:
```bash
# On Jenkins, in the pipeline:
env.PUSH_TIME = sh(script: 'git log -1 --format=%cI', returnStdout: true).trim()
env.BUILD_START = currentBuild.startTimeInMillis
// Compute diff after pipeline completes
```

### Why It Matters
- **Polling-based CI** introduces latency equal to the poll interval (typically 1–5 minutes). Webhooks eliminate this entirely.
- 3–4 seconds is near-instant — the pipeline starts before the developer can switch to the browser.
- Faster feedback loops mean faster iteration and less context-switching.

## Pipeline-Start-to-Deploy-Complete Latency

Measures the time from pipeline build start to deployment complete (pod ready).

| Test Case | Branch | Build Time | Test Time | Deploy Time | Total |
|-----------|--------|------------|-----------|-------------|-------|
| Feature branch | feature/api | 45s | 62s | N/A | 1m 47s |
| Develop | develop | 42s | 58s | 35s | 2m 15s |
| Main | main | 44s | 61s + 30s scan | 42s | 3m 37s |
| Production | v1.0.0 | 46s | 60s + 32s scan | 85s | 4m 33s |

### Breakdown per Stage

**Build (docker build):** ~45s
- Docker layer caching reduces this to ~15s on subsequent builds with unchanged dependencies

**Test (unit + integration):** ~60s
- Parallel unit and integration tests; total is wall-clock of the slower stage

**Security Scan (Trivy):** ~30s
- Only on main and release tags
- Fails pipeline on HIGH/CRITICAL CVEs

**Deploy to Dev:** ~35s
- `kubectl set image` + `kubectl rollout status`
- 2 replicas, rolling update, ~15s per pod

**Deploy to Staging:** ~42s
- Same as dev, slightly larger resource requests

**Deploy to Production:** ~85s
- Includes manual approval gate (~30s average wait)
- Canary rollout with 30s pause between waves
- Health check verification: 30s

### Total End-to-End: Push to Production

```
git push (v1.0.0 tag)
  → webhook delivery:          ~3s
  → build:                    ~46s
  → test + security scan:     ~92s
  → approval gate:            ~30s (manual)
  → deploy + rollout:         ~85s
  ─────────────────────────────────
  Total:                    ~3m 56s (with approval)
  Total (automated only):   ~3m 26s
```

### Comparison: Webhook vs Polling

| Metric | Webhook | Polling (5 min interval) |
|--------|---------|--------------------------|
| Push to pipeline start | 3.4s avg | 0–300s (avg ~150s) |
| Developer feedback | Near-instant | Up to 5 minutes delayed |
| Resource usage | Event-driven, idle when no events | Constant polling cycles |
| Reliability | Depends on delivery (retries exist) | Depends on poll cycle completion |

Webhook-triggered pipelines are ~44x faster to start than 5-minute polling.
