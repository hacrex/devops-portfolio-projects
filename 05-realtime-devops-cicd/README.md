# 5. Real-Time DevOps CI/CD Project

## Overview
Where Project 4 focuses on pipeline stages and promotion strategy, this project focuses on **triggering**: webhook-driven, event-based automation so that a push, a PR, or even an external event (e.g., a cron job, an S3 upload, an SNS message) kicks off the right pipeline with no manual intervention — the "real-time" in the title refers to reaction speed and event-driven architecture, not literally real-time systems.

## Architecture
```
GitHub webhook (push/PR event) ──► Jenkins/GitHub Actions runner
                                         │
                                         ▼
                                  Pipeline triggers within seconds
                                         │
      ┌──────────────────────────────────┼───────────────────────────┐
      ▼                                  ▼                            ▼
 Build & test                    Notify Slack channel           Update deployment
 (on every push)                 (pipeline status,               status dashboard
                                   pass/fail, duration)           (Grafana/custom)
                                         │
                                         ▼
                              Auto-deploy to environment
                              matched to branch/tag pattern
```

## Pipeline Stages
1. **Webhook configuration** — GitHub/GitLab webhook configured to fire on push, PR open, PR merge, and tag creation events, hitting the CI server's webhook endpoint directly (not polling).
2. **Trigger validation** — pipeline verifies the webhook payload/signature (HMAC secret) before acting, to prevent spoofed trigger requests.
3. **Branch-based routing** — different branches trigger different pipeline behaviors: `feature/*` → build+test only, `develop` → deploy to dev, `main` → deploy to staging, tags matching `v*` → deploy to production.
4. **Build, test, security scan** — same core CI stages as the other projects.
5. **Real-time notifications** — Slack/Teams webhook posts pipeline status (started, passed, failed, deployed) as it happens, with a link to logs.
6. **Auto-deploy** — matched environment receives the new build automatically, no manual `kubectl`/`docker` commands.
7. **Status dashboard** — a lightweight dashboard (Grafana panel or simple webpage) shows the last N pipeline runs, their status, and current deployed version per environment.

## Tools Used
GitHub/GitLab webhooks, Jenkins (with the GitHub/GitLab plugin) or GitHub Actions, ngrok (for local Jenkins to receive webhooks during development/testing), Slack API/webhooks, Docker, Kubernetes, Prometheus/Grafana for the status dashboard.

## What to Build & Push to This Folder
- `webhook-config/` — documented webhook setup (payload URL, events subscribed, secret handling) — a screenshot of the GitHub webhook settings page plus delivery logs
- `Jenkinsfile` (Multibranch Pipeline) or `.github/workflows/` with branch-based job routing
- `scripts/verify-webhook-signature.sh` or equivalent — actual signature verification logic, not just "assume it's legit"
- `notifications/slack-notify.sh` — the actual notification integration
- `docs/trigger-latency.md` — measured time from push to pipeline start, and from pipeline start to deployment complete

## Interview Points

**What this project proves:** you understand event-driven automation and webhook security, not just "I clicked build manually to make the demo work."

**Likely questions and how to answer them:**
- *"How do you verify a webhook request is actually from GitHub/GitLab and not spoofed?"* — HMAC signature verification using the shared webhook secret; the CI server recomputes the signature over the payload and compares it to the `X-Hub-Signature-256` header before processing. If you skipped this, say so honestly and name it as a known gap.
- *"What's the difference between webhook-triggered and polling-based CI?"* — Polling checks for changes on an interval (wastes resources, adds latency up to the poll interval); webhooks push events instantly, so pipelines start within seconds of the actual git event.
- *"How did you test webhooks while developing locally, before you had a public endpoint?"* — ngrok or a similar tunnel to expose your local Jenkins to GitHub's webhook delivery — a very common real answer, don't be embarrassed by it.
- *"What happens if your webhook receiver is down when GitHub tries to deliver the event?"* — GitHub retries webhook deliveries with backoff for a period; explain you'd also want a periodic reconciliation job as a safety net in a production setup, not rely purely on webhook delivery guarantees.
- *"How do you prevent two pipeline runs from colliding if two pushes happen close together?"* — Concurrency controls: Jenkins' `disableConcurrentBuilds()` or GitHub Actions' `concurrency` key with a group per branch, canceling or queuing the older run.
- *"What did you measure for trigger latency, and why does it matter?"* — Have your actual number from `docs/trigger-latency.md` ready — this is the kind of concrete detail that separates "I read about this" from "I built and measured this."

**Weak spots to pre-empt:** if your "real-time" trigger is really just standard CI polling because you never got webhooks working end-to-end, be upfront about that rather than calling it real-time — reviewers who dig into "how does the webhook secret verification work" will find the gap fast if it's not real.

**Numbers/metrics to have ready:** push-to-pipeline-start latency, pipeline-start-to-deploy-complete latency, webhook delivery success rate (visible in GitHub's webhook delivery log).
