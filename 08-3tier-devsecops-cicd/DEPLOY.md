# Deployment Guide: 3-Tier DevSecOps CI/CD

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| AWS CLI | v2.x | All AWS services |
| eksctl | latest | EKS provisioning |
| Terraform | >= 1.5 | RDS infrastructure |
| kubectl | v1.28+ | K8s management |
| Helm | v3.12+ | Package management |
| Docker | v24+ | Container builds |
| GitHub account | - | CI/CD pipeline |
| Node.js | v20.x | Local development |

Architecture tiers:
- **Presentation:** React app → S3 + CloudFront
- **Application:** Node.js API → EKS cluster
- **Data:** PostgreSQL → RDS

---

## Step 1: Create VPC with Public/Private Subnets

```bash
# Create the VPC
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text)
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=devsecops-vpc

# Enable DNS support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames

# Create Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID

# Create public subnets
PUBLIC_SUBNET_1=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone us-east-1a --query 'Subnet.SubnetId' --output text)
PUBLIC_SUBNET_2=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone us-east-1b --query 'Subnet.SubnetId' --output text)

# Create private subnets
PRIVATE_SUBNET_1=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.10.0/24 --availability-zone us-east-1a --query 'Subnet.SubnetId' --output text)
PRIVATE_SUBNET_2=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.11.0/24 --availability-zone us-east-1b --query 'Subnet.SubnetId' --output text)

# Tag subnets
aws ec2 create-tags --resources $PUBLIC_SUBNET_1 $PUBLIC_SUBNET_2 --tags Key=Tier,Value=public
aws ec2 create-tags --resources $PRIVATE_SUBNET_1 $PRIVATE_SUBNET_2 --tags Key=Tier,Value=private

# Create NAT Gateway (for private subnet internet access)
EIP_ALLOC=$(aws ec2 allocate-address --query 'AllocationId' --output text)
NAT_GW_ID=$(aws ec2 create-nat-gateway --subnet-id $PUBLIC_SUBNET_1 --allocation-id $EIP_ALLOC --query 'NatGateway.NatGatewayId' --output text)

# Wait for NAT Gateway
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW_ID

# Create route tables
PUBLIC_RT=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $PUBLIC_RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
aws ec2 associate-route-table --route-table-id $PUBLIC_RT --subnet-id $PUBLIC_SUBNET_1
aws ec2 associate-route-table --route-table-id $PUBLIC_RT --subnet-id $PUBLIC_SUBNET_2

PRIVATE_RT=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $PRIVATE_RT --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GW_ID
aws ec2 associate-route-table --route-table-id $PRIVATE_RT --subnet-id $PRIVATE_SUBNET_1
aws ec2 associate-route-table --route-table-id $PRIVATE_RT --subnet-id $PRIVATE_SUBNET_2

# Create Security Groups
APP_SG=$(aws ec2 create-security-group --group-name devsecops-app-sg --description "Application tier SG" --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 create-tags --resources $APP_SG --tags Key=Name,Value=devsecops-app-sg
```

Verify:

```bash
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=devsecops-vpc"
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID"
```

---

## Step 2: Create IAM OIDC Roles for GitHub Actions

```bash
# Create IAM OIDC provider for GitHub Actions
OIDC_URL=$(aws eks describe-cluster --name devsecops-eks-cluster --query "cluster.identity.oidc.issuer" --output text | sed 's|https://||')

# Install eksctl if not installed
curl --silent --location "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Create the EKS cluster first (if not already created)
eksctl create cluster \
  --name devsecops-eks-cluster \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 3 \
  --managed

# Create IAM roles for GitHub Actions
eksctl create iamserviceaccount \
  --cluster=devsecops-eks-cluster \
  --name=github-actions-deployer \
  --namespace=default \
  --role-name=GitHubActionsEKSDeploy \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonEKSClusterPolicy \
  --approve

# Create ECR push role
eksctl create iamserviceaccount \
  --cluster=devsecops-eks-cluster \
  --name=github-actions-ecr \
  --namespace=default \
  --role-name=GitHubActionsECRPush \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser \
  --approve

# Create migration role
eksctl create iamserviceaccount \
  --cluster=devsecops-eks-cluster \
  --name=github-actions-migration \
  --namespace=default \
  --role-name=GitHubActionsMigrationRole \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonRDSFullAccess \
  --approve
```

---

## Step 3: Run Terraform for RDS

```bash
cd data-tier/terraform

# Initialize
terraform init

# Create a terraform.tfvars file
cat > terraform.tfvars <<EOF
environment    = "production"
db_username    = "admin"
db_password    = "YOUR_SECURE_PASSWORD"
instance_class = "db.t3.medium"
EOF

# Plan
terraform plan -out=tfplan

# Apply
terraform apply tfplan
```

Note the RDS endpoint from outputs:

```bash
terraform output
```

Store DB credentials in AWS Secrets Manager:

```bash
aws secretsmanager create-secret \
  --name devsecops/production/db-credentials \
  --secret-string '{"host":"YOUR_RDS_ENDPOINT","dbname":"appdb","username":"admin","password":"YOUR_PASSWORD"}'
```

---

## Step 4: Create S3 Bucket + CloudFront Distribution

```bash
# Create S3 bucket for presentation tier
aws s3 mb s3://devsecops-presentation-assets --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket devsecops-presentation-assets \
  --versioning-configuration Status=Enabled

# Block public access (CloudFront will access via OAC)
aws s3api put-public-access-block \
  --bucket devsecops-presentation-assets \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Create CloudFront OAC
cat > /tmp/oac.json <<EOF
{
  "CallerReference": "devsecops-oac-$(date +%s)",
  "OriginAccessControlConfig": {
    "Name": "devsecops-s3-oac",
    "OriginAccessControlOriginType": "s3",
    "SigningBehavior": "always",
    "SigningProtocol": "sigv4"
  }
}
EOF

OAC_ID=$(aws cloudfront create-origin-access-control \
  --origin-access-control-config file:///tmp/oac.json \
  --query 'OriginAccessControl.Id' --output text)

# Create CloudFront distribution (use AWS Console for complex configs or below CLI)
cat > /tmp/cf-config.json <<EOF
{
  "CallerReference": "devsecops-cf-$(date +%s)",
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "S3-devsecops-presentation",
        "DomainName": "devsecops-presentation-assets.s3.amazonaws.com",
        "OriginAccessControlId": "${OAC_ID}",
        "S3OriginConfig": {
          "OriginAccessIdentity": ""
        }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "S3-devsecops-presentation",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"]
    },
    "ForwardedValues": {
      "QueryString": false,
      "Cookies": { "Forward": "none" }
    },
    "MinTTL": 0,
    "DefaultTTL": 86400,
    "MaxTTL": 31536000
  },
  "Comment": "DevSecOps Presentation Tier",
  "Enabled": true,
  "CallerReference": "devsecops-cf-$(date +%s)"
}
EOF

CF_DIST_ID=$(aws cloudfront create-distribution \
  --distribution-config file:///tmp/cf-config.json \
  --query 'Distribution.Id' --output text)

echo "CloudFront Distribution ID: $CF_DIST_ID"
echo "CloudFront Domain: $(aws cloudfront get-distribution --id $CF_DIST_ID --query 'Distribution.DomainName' --output text)"
```

Add S3 bucket policy for CloudFront access:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
cat > /tmp/bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipal",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::devsecops-presentation-assets/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${CF_DIST_ID}"
        }
      }
    }
  ]
}
EOF

aws s3api put-bucket-policy \
  --bucket devsecops-presentation-assets \
  --policy file:///tmp/bucket-policy.json
```

---

## Step 5: Create EKS Cluster with Application Namespace

```bash
# Create EKS cluster (if not already created in Step 2)
eksctl create cluster \
  --name devsecops-eks-cluster \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 3 \
  --managed

# Create application namespace
kubectl create namespace application

# Create K8s secrets for DB credentials
kubectl create secret generic db-credentials \
  --namespace application \
  --from-literal=host=YOUR_RDS_ENDPOINT \
  --from-literal=password=YOUR_DB_PASSWORD \
  --from-literal=dbname=appdb
```

---

## Step 6: Create K8s Secrets

```bash
# Application tier secrets
kubectl create secret generic db-credentials \
  --namespace application \
  --from-literal=host=YOUR_RDS_ENDPOINT \
  --from-literal=password=YOUR_DB_PASSWORD \
  --from-literal=dbname=appdb \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

## Step 7: Configure GitHub Secrets

Go to your GitHub repo > Settings > Secrets and variables > Actions. Add:

| Secret Name | Value |
|-------------|-------|
| `AWS_ACCOUNT_ID` | Your 12-digit AWS account ID |
| `AWS_ROLE_ARN_ECR` | `arn:aws:iam::ACCOUNT:role/GitHubActionsECRPush` |
| `AWS_ROLE_ARN_EKS` | `arn:aws:iam::ACCOUNT:role/GitHubActionsEKSDeploy` |
| `AWS_ROLE_ARN_MIGRATION` | `arn:aws:iam::ACCOUNT:role/GitHubActionsMigrationRole` |
| `SONAR_TOKEN` | SonarQube auth token |
| `SNYK_TOKEN` | Snyk API token |

---

## Step 8: Create IAM Roles for Each Tier

The EKS service accounts were created in Step 2. Verify:

```bash
# Check service accounts
kubectl get sa -A | grep github-actions

# Check IAM role trust policy
aws iam get-role --role-name GitHubActionsEKSDeploy --query 'Role.AssumeRolePolicyDocument'
```

---

## Step 9: Push Presentation Tier

```bash
git add presentation-tier/
git commit -m "feat: presentation tier deployment"
git push origin main
```

Monitor in GitHub Actions. The workflow:
1. Lint + typecheck
2. Build React app
3. Deploy to S3
4. Invalidate CloudFront

Verify:

```bash
aws s3 ls s3://devsecops-presentation-assets/
# Should contain index.html, static/, etc.
```

---

## Step 10: Push Application Tier

```bash
git add application-tier/
git commit -m "feat: application tier deployment"
git push origin main
```

Monitor in GitHub Actions. The workflow:
1. Unit tests
2. SonarQube SAST
3. Snyk SCA
4. Docker build + push to ECR
5. Trivy scan
6. Deploy to EKS

Verify:

```bash
kubectl get pods -n application
kubectl rollout status deployment/api-deployment -n application
curl http://YOUR_APP_ENDPOINT/health
```

---

## Step 11: Run Migration Pipeline

Go to GitHub > Actions > Database Migrations > Run workflow:

1. Select target environment (staging or production)
2. Leave migration_version empty for all pending
3. Click "Run workflow"

Verify:

```bash
# Check migration status via Flyway
flyway -url=jdbc:postgresql://YOUR_RDS:5432/appdb \
  -user=admin \
  -password=YOUR_PASSWORD \
  info
```

---

## Step 12: Configure WAF Rules

> See `docs/waf-rules.md` for detailed WAF configuration.

```bash
# Create WAF WebACL
cat > /tmp/waf-config.json <<EOF
{
  "Name": "devsecops-waf",
  "Scope": "CLOUDFRONT",
  "DefaultAction": { "Allow": {} },
  "Rules": [
    {
      "Name": "RateLimit",
      "Priority": 1,
      "Action": { "Block": {} },
      "Statement": {
        "RateBasedStatement": {
          "Limit": 2000,
          "AggregateKeyType": "IP"
        }
      },
      "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "RateLimit"
      }
    },
    {
      "Name": "AWSManagedRulesCommonRuleSet",
      "Priority": 2,
      "OverrideAction": { "None": {} },
      "Statement": {
        "ManagedRuleGroupStatement": {
          "VendorName": "AWS",
          "Name": "AWSManagedRulesCommonRuleSet"
        }
      },
      "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "CommonRuleSet"
      }
    }
  ],
  "VisibilityConfig": {
    "SampledRequestsEnabled": true,
    "CloudWatchMetricsEnabled": true,
    "MetricName": "devsecops-waf"
  }
}
EOF

WAF_ACL_ARN=$(aws wafv2 create-web-acl \
  --name devsecops-waf \
  --scope CLOUDFRONT \
  --default-action '{"Allow":{}}' \
  --rules file:///tmp/waf-config.json \
  --visibility-config '{"SampledRequestsEnabled":true,"CloudWatchMetricsEnabled":true,"MetricName":"devsecops-waf"}' \
  --query 'Summary.ARN' --output text)

# Associate WAF with CloudFront
aws wafv2 associate-web-acl \
  --web-acl-arn $WAF_ACL_ARN \
  --resource-arn "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${CF_DIST_ID}"
```

---

## Step 13: Verify All Tiers

```bash
# Presentation tier (S3 + CloudFront)
curl -I https://YOUR_CLOUDFRONT_DOMAIN/
# Should return 200 with React app

# Application tier (EKS)
kubectl get pods -n application
curl https://YOUR_APP_ENDPOINT/health
# Should return {"status":"UP"}

# Data tier (RDS)
psql -h YOUR_RDS_ENDPOINT -U admin -d appdb -c "\dt"
# Should list users and movies tables

# WAF
curl -I https://YOUR_CLOUDFRONT_DOMAIN/
# Check WAF metrics in CloudWatch

# Full end-to-end
curl https://YOUR_CLOUDFRONT_DOMAIN/api/videos
# Should return data from RDS through the API
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| CloudFront returns 403 | Check S3 bucket policy allows the CloudFront distribution |
| EKS deploy fails with IAM error | Verify service account has correct IAM role annotation |
| RDS connection refused | Check VPC security groups allow traffic from EKS nodes |
| WAF blocks legitimate traffic | Check WAF logs in CloudWatch, adjust rules |
| Migration fails | Verify Secrets Manager secret exists and DB is reachable from GitHub Actions runner |
| S3 sync doesn't update | Check CloudFront cache invalidation completed |

---

## Cleanup

```bash
# Delete EKS cluster
eksctl delete cluster --name devsecops-eks-cluster --region us-east-1

# Delete RDS instance
cd data-tier/terraform
terraform destroy

# Delete S3 bucket
aws s3 rb s3://devsecops-presentation-assets --force

# Delete CloudFront distribution (must disable first)
aws cloudfront update-distribution --id $CF_DIST_ID --distribution-config '{"Enabled":false}'
# Wait ~15 min, then:
aws cloudfront delete-distribution --id $CF_DIST_ID

# Delete WAF
aws wafv2 disassociate-web-acl --web-acl-arn $WAF_ACL_ARN --resource-arn "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${CF_DIST_ID}"
aws wafv2 delete-web-acl --name devsecops-waf --scope CLOUDFRONT --id $(echo $WAF_ACL_ARN | awk -F'/' '{print $NF}')

# Delete VPC resources
aws ec2 delete-subnet --subnet-id $PUBLIC_SUBNET_1
aws ec2 delete-subnet --subnet-id $PUBLIC_SUBNET_2
aws ec2 delete-subnet --subnet-id $PRIVATE_SUBNET_1
aws ec2 delete-subnet --subnet-id $PRIVATE_SUBNET_2
aws ec2 delete-nat-gateway --nat-gateway-id $NAT_GW_ID
aws ec2 release-address --allocation-id $EIP_ALLOC
aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID
aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
aws ec2 delete-vpc --vpc-id $VPC_ID
```
