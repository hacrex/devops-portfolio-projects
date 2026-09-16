# Network Architecture — 3-Tier DevSecOps

## VPC Layout

```
VPC: 10.0.0.0/16 (devsecops-vpc)
│
├── PUBLIC SUBNETS (route table → Internet Gateway)
│   ├── 10.0.1.0/24  (us-east-1a)  — ALB / WAF
│   └── 10.0.2.0/24  (us-east-1b)  — ALB / WAF
│
├── PRIVATE SUBNETS — Application Tier (route table → NAT Gateway)
│   ├── 10.0.10.0/24 (us-east-1a)  — EKS Worker Nodes
│   └── 10.0.11.0/24 (us-east-1b)  — EKS Worker Nodes
│
└── PRIVATE SUBNETS — Data Tier (no NAT, no IGW — isolated)
    ├── 10.0.20.0/24 (us-east-1a)  — RDS Primary
    └── 10.0.21.0/24 (us-east-1b)  — RDS Standby
```

## Security Group Rules

### SG: `devsecops-alb-sg` (Load Balancer)
| Direction | Port  | Protocol | Source            | Purpose                    |
|-----------|-------|----------|-------------------|----------------------------|
| Inbound   | 443   | TCP      | 0.0.0.0/0         | HTTPS from internet         |
| Inbound   | 80    | TCP      | 0.0.0.0/0         | HTTP (redirect to HTTPS)    |
| Outbound  | 3000  | TCP      | devsecops-app-sg  | Forward to app tier         |

### SG: `devsecops-app-sg` (EKS Worker Nodes)
| Direction | Port  | Protocol | Source            | Purpose                    |
|-----------|-------|----------|-------------------|----------------------------|
| Inbound   | 3000  | TCP      | devsecops-alb-sg  | API traffic from ALB        |
| Inbound   | 10250 | TCP      | 10.0.0.0/16       | Kubelet from control plane  |
| Inbound   | 53    | UDP      | 10.0.0.0/16       | DNS resolution              |
| Outbound  | 5432  | TCP      | devsecops-rds-sg  | PostgreSQL to data tier     |
| Outbound  | 443   | TCP      | 0.0.0.0/0         | ECR, Secrets Manager, etc.  |

### SG: `devsecops-rds-sg` (RDS)
| Direction | Port  | Protocol | Source            | Purpose                    |
|-----------|-------|----------|-------------------|----------------------------|
| Inbound   | 5432  | TCP      | devsecops-app-sg  | PostgreSQL from app tier ONLY|
| Outbound  | 0     | -1       | 0.0.0.0/0         | Default (limited by NACL)   |

## Traffic Flow

```
Internet
   │
   ▼
AWS WAF (rate limit, SQLi, XSS, bad IPs)
   │
   ▼
Application Load Balancer (public subnets)
   │  terminates TLS
   ▼
EKS Ingress Controller (private subnets)
   │  routes /api/* to api-service:80
   ▼
API Pods (ClusterIP Service)
   │  fetches DB creds from Secrets Manager via IAM role
   ▼
RDS PostgreSQL (isolated private subnets, no internet route)
   │  encrypted at rest with KMS
```

## Key Isolation Points

1. **RDS has no internet route** — private subnets with no NAT Gateway or Internet Gateway attachment
2. **RDS security group only allows inbound from app tier SG** — not a CIDR range; ensures only API pods can connect
3. **Application tier uses IAM roles for AWS access** — no hardcoded credentials; pods assume a service account linked to an IAM role via IRSA
4. **WAF sits in front of ALB** — blocks malicious traffic before it reaches any compute resource
5. **Schema migrations run from CI/CD only** — no bastion host or direct database access from developer machines
