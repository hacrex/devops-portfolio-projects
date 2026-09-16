# Rollback Test Documentation

## Test Scenario

Deliberately deploy a broken image to verify automatic rollback triggers and recovers traffic to the last stable release.

## Steps to Reproduce

### 1. Record Current State

```bash
# Note the current healthy revision
helm history webapp -n webapp-prod
# Example output:
# REVISION  STATUS     DESCRIPTION
# 1         superseded Install complete
# 2         deployed   Upgrade complete
```

### 2. Deploy a Broken Image

Push an image with a failing readiness probe (e.g., HTTP server returns 500 on `/healthz`):

```bash
# Manually simulate what the pipeline does
helm upgrade --install webapp ./helm-chart \
  --namespace webapp-prod \
  --set image.tag=broken-v1 \
  --wait \
  --timeout 5m
```

### 3. Observe Failure

The `helm upgrade --wait` command will time out because pods never reach Ready state:

```
Error: timed out waiting for the condition
```

### 4. Pipeline Behavior (Automated)

When this occurs inside the Jenkins pipeline:

1. The **Health Check Gate** stage fails (`kubectl rollout status` times out after 300s)
2. The **post failure** block executes `helm rollback webapp 0`
3. Kubernetes continues serving traffic from the previous ReplicaSet during the entire failure window (rolling update guarantees)
4. After rollback completes, all pods run the last known-good image

### 5. Verify Rollback

```bash
# Confirm revision incremented and deployment is healthy
helm history webapp -n webapp-prod
kubectl rollout status deployment/webapp -n webapp-prod
kubectl get pods -n webapp-prod -l app.kubernetes.io/name=webapp
```

Expected: pods are Running and Ready, serving the previous image tag.

## What Happens During the Failure Window

| Time | Event |
|------|-------|
| T+0s | New ReplicaSet created with broken image |
| T+0s to T+15s | Kubernetes starts new pods, old pods still handle traffic |
| T+15s | New pods fail readiness probe — never receive traffic |
| T+300s | `kubectl rollout status` times out |
| T+300s | Pipeline stage fails, triggers `helm rollback` |
| T+300s to T+480s | Helm rollback runs, old ReplicaSet scaled back up |
| T+480s | All traffic served by stable release |

## Expected Results

- **Zero downtime**: old pods continue serving throughout the failure
- **Automatic recovery**: no manual intervention required
- **Release history**: `helm history` shows revision 3 (failed) and revision 4 (rollback to revision 2's state)
- **Audit trail**: Jenkins console log shows rollback completion message

## Configuration Notes

The `maxUnavailable: 0` and `maxSurge: 1` settings in the Deployment ensure at least one old pod remains running during any rollout, which is what prevents downtime during both failed deploys and rollbacks.
