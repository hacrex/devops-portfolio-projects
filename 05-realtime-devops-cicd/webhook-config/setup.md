# Webhook Configuration

## GitHub Webhook Setup

### Settings
- **Payload URL:** `https://jenkins.yourdomain.com/github-webhook/`
- **Content type:** `application/json`
- **Secret:** Stored in Jenkins credentials as `github-webhook-secret` (never committed to repo)
- **SSL verification:** Enable (Require SSL)

### Events Subscribed
| Event | Purpose |
|-------|---------|
| Push | Triggers pipeline on any branch push or tag creation |
| Pull request | Triggers build + test on PR open, synchronize, reopen |
| Pull request review | Optional — triggers on PR approval for auto-merge |

### Branch-Based Routing
The Jenkinsfile inspects `refs/heads` or `refs/tags` from the webhook payload to route:

| Ref Pattern | Pipeline Behavior |
|-------------|-------------------|
| `feature/*` | Build + test only, no deploy |
| `develop` | Build + test + deploy to dev |
| `main` | Build + test + deploy to staging |
| `v*` (tags) | Build + test + security scan + deploy to prod |

### Secret Handling
The HMAC secret is stored in Jenkins as a **Secret Text** credential bound to the `github-webhook-secret` credential ID. The pipeline reads it and passes it to the signature verification script:

```groovy
withCredentials([string(credentialsId: 'github-webhook-secret', variable: 'WEBHOOK_SECRET')]) {
    sh './scripts/verify-webhook-signature.sh "$WEBHOOK_SECRET"'
}
```

GitHub signs every payload with this secret using HMAC-SHA256. The signature arrives in the `X-Hub-Signature-256` header as `sha256=<hex-digest>`.

### Example GitHub Webhook Configuration
```
Repository → Settings → Webhooks → Add webhook

Payload URL:    https://jenkins.yourdomain.com/github-webhook/
Content type:   application/json
Secret:         <your-hmac-secret>
SSL verify:     Enabled

Which events would you like to trigger this webhook?
  ◉  Just the push event
  ◉  Let me select individual events.
     ☑ Pull requests
```

### Delivery Logs
GitHub provides delivery logs under the webhook settings page. Each delivery shows:
- Status code from your receiver
- Response body
- Request/response headers
- Redacted payload (secret is never shown after initial save)

Use delivery logs to debug failed deliveries — they show exactly what GitHub sent and what your endpoint returned.

### Local Development with ngrok
During local development, Jenkins is not publicly reachable. Use ngrok to tunnel:

```bash
ngrok http 8080
# Use the https URL as the Payload URL in GitHub
# e.g., https://abc123.ngrok.io/github-webhook/
```

Remember to update the Payload URL back to production after testing.

### Webhook Delivery Retries
GitHub retries failed deliveries with exponential backoff:
- Up to 5 retries over ~24 hours
- A delivery is considered successful on HTTP 2xx response
- Non-2xx or timeout triggers retry

Do not rely solely on webhook delivery for critical workflows. A periodic reconciliation job (e.g., polling the GitHub API every 5 minutes) is a safety net for missed events.
