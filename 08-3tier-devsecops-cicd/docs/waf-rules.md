# AWS WAF Rules — 3-Tier DevSecOps

## Rule Summary

| Rule Name                         | Priority | Action  | What It Blocks                           |
|-----------------------------------|----------|---------|------------------------------------------|
| Rate Limiting                     | 1        | Block   | >2000 requests per IP per 5-minute window|
| AWS Managed — SQLi                | 2        | Block   | SQL injection patterns (OWASP CRS)       |
| AWS Managed — XSS                 | 3        | Block   | Cross-site scripting patterns            |
| AWS Managed — Known Bad Inputs    | 4        | Block   | Exploitable paths (/etc/passwd, etc.)    |
| IP Reputation List                | 5        | Block   | IPs associated with botnets, proxies     |
| Geographic Restriction            | 6        | Block   | Traffic from high-risk countries          |
| Custom — Admin Path Protection    | 7        | Block   | /admin, /debug, /metrics from public     |
| Log All Requests                  | 100      | Count   | All remaining requests (for monitoring)  |

## Rule Details

### 1. Rate Limiting
- **Type:** Rate-based rule
- **Limit:** 2000 requests per IP per 5-minute sliding window
- **Action:** Block + CAPTCHA challenge
- **Aggregate key:** IP address
- **Use case:** Prevents DDoS, credential stuffing, brute-force login attempts

### 2. SQL Injection (AWS Managed — AWSManagedRulesSQLiRuleSet)
- **Type:** Managed rule group
- **Action:** Block
- **Targets:** Query strings, body, URI, headers
- **Use case:** Blocks classic SQLi attacks (union-based, blind, time-based) against the API and any query parameters

### 3. Cross-Site Scripting (AWS Managed — AWSManagedRulesKnownBadInputsRuleSet)
- **Type:** Managed rule group
- **Action:** Block
- **Targets:** Query strings, body, URI, headers
- **Use case:** Blocks reflected and stored XSS payloads in user input

### 4. Known Bad Inputs (AWS Managed — AWSManagedRulesKnownBadInputsRuleSet)
- **Type:** Managed rule group
- **Action:** Block
- **Matches:** Log4j exploit strings, path traversal (`../`), shell injection patterns, common scanner paths
- **Use case:** Blocks reconnaissance and exploitation attempts against known CVEs

### 5. IP Reputation List (AWS Managed — AWSManagedRulesAmazonIpReputationList)
- **Type:** Managed rule group
- **Action:** Block
- **Sources:** AWS threat intelligence, Tor exit nodes, known proxy/VPN endpoints
- **Use case:** Reduces traffic from known malicious sources without manual IP blocklist maintenance

### 6. Geographic Restriction
- **Type:** Geo match
- **Action:** Block
- **Countries:** (configure based on business requirements)
- **Use case:** Blocks traffic from regions where the application has no users

### 7. Custom — Admin Path Protection
- **Type:** byte-match rule
- **Action:** Block
- **Match:** URI paths starting with /admin, /debug, /metrics, /.env
- **Use case:** Prevents public access to internal/debug endpoints that should only be reachable within the VPC

### 8. Log All Requests
- **Type:** Counting rule
- **Action:** Count (no block)
- **Priority:** Lowest (evaluated last)
- **Use case:** Enables logging and metrics for all traffic patterns; used with CloudWatch dashboards and alerts

## WAF Association

```
WAF Web ACL
    │
    ├── Associated with: Application Load Balancer
    ├── Default action: Allow
    └── CloudWatch metrics: Enabled
        ├── Metric name: DevSecOpsWAF
        ├── Sampled requests: Enabled
        └── CloudWatch alarm: >50 blocked requests in 5 min → SNS alert
```

## Monitoring & Response

- CloudWatch metric `BlockedRequests` with alarm threshold of 50 requests per 5-minute period
- WAF logs delivered to S3 bucket `devsecops-waf-logs` with Athena table for ad-hoc querying
- Sampled requests viewable in WAF console for real-time inspection
- Regular rule tuning: review blocked requests monthly to reduce false positives
