# Rollback Runbook

## Overview

This document outlines procedures for rolling back deployments in the Ultimate CI/CD Pipeline project. It covers automated rollback via the GitHub Actions pipeline and manual rollback procedures.

## Automated Rollback

The pipeline automatically triggers rollback when the canary deployment to production fails during verification.

### How Automated Rollback Works

1. **Canary Failure Detection**: Flagger monitors error rates, latency, and success rates during canary analysis.
2. **Automatic Rollback**: If thresholds are breached (error rate > 1%, p95 latency > 500ms, or success rate < 99%), Flagger rolls back the canary and restores the previous stable version.
3. **Pipeline Notification**: The pipeline posts a notification to Slack indicating the rollback occurred.

### Checking Canary Status

```bash
kubectl get canary capstone-app -n production
```

Expected output for a healthy canary:
```
NAME            STATUS        WEIGHT   LASTTRANSITIONTIME
capstone-app    Succeeded     100      2024-01-15T10:30:00Z
```

Expected output for a failed/rolled-back canary:
```
NAME            STATUS        WEIGHT   LASTTRANSITIONTIME
capstone-app    Failed        0        2024-01-15T10:35:00Z
```

## Manual Rollback

If automated rollback did not trigger or you need to perform an immediate manual rollback:

### Step 1: Identify the Last Known Good Version

```bash
# List recent deployments
kubectl rollout history deployment/capstone-app -n production

# Check current image
kubectl get deployment capstone-app -n production -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### Step 2: Roll Back to Previous Version

```bash
# Undo the last rollout
kubectl rollout undo deployment/capstone-app -n production

# Monitor the rollback progress
kubectl rollout status deployment/capstone-app -n production --timeout=300s
```

### Step 3: Roll Back to a Specific Revision

```bash
# View all revisions
kubectl rollout history deployment/capstone-app -n production

# Roll back to a specific revision number
kubectl rollout undo deployment/capstone-app -n production --to-revision=5
```

### Step 4: Verify the Rollback

```bash
# Check deployment status
kubectl get deployment capstone-app -n production

# Check pod health
kubectl get pods -n production -l app=capstone-app

# Test the endpoint
curl -sf https://api.example.com/health
curl -sf https://api.example.com/api/endpoint
```

## Rollback Checklist

- [ ] Confirm the incident or failure
- [ ] Notify the team via Slack #incidents channel
- [ ] Perform the rollback (automated or manual)
- [ ] Verify the application is healthy
- [ ] Run smoke tests
- [ ] Check monitoring dashboards for error rates and latency
- [ ] Update the incident ticket with rollback details
- [ ] Schedule a post-mortem if needed

## Database Rollback

If the deployment included database migrations:

```bash
# Check for pending migrations
kubectl exec -it capstone-app-xxxxx -n production -- java -jar app.jar --spring.main.web-application-type=none --spring.flyway.locations=classpath:db/migration --spring.flyway.validate-on-migrate=true

# If using Flyway, migrate to the previous version
kubectl exec -it capstone-app-xxxxx -n production -- java -jar app.jar --spring.main.web-application-type=none --flyway.target=20240110_001
```

## Emergency Contacts

| Role | Name | Contact |
|------|------|---------|
| On-call Engineer | Team Lead | Slack: @team-lead |
| Platform Team | Platform Engineer | Slack: @platform |
| DBA | Database Admin | Slack: @dba |

## Post-Rollback Actions

1. **Root Cause Analysis**: Investigate why the deployment failed
2. **Fix the Issue**: Address the root cause in the codebase
3. **Test Thoroughly**: Run integration and load tests on the fix
4. **Re-deploy**: Push the fix through the standard pipeline
5. **Monitor**: Watch production metrics for 30 minutes after re-deployment
