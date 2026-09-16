# Deployment Guide: GitLab CI/CD with Terraform IaC

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| AWS CLI | v2.x | AWS resource management |
| Terraform | >= 1.5.0 | Infrastructure as Code |
| GitLab account | - | CI/CD pipeline |
| GitLab Runner | - | Pipeline execution |

### AWS Account Setup

```bash
aws configure
aws sts get-caller-identity
```

---

## Step 1: Bootstrap S3 State Buckets and DynamoDB Tables

Terraform needs remote state storage before it can manage anything. Bootstrap both environments:

```bash
# Dev state bucket + lock table
aws s3api create-bucket \
  --bucket devops-portfolio-tfstate-dev \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket devops-portfolio-tfstate-dev \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket devops-portfolio-tfstate-dev \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws dynamodb create-table \
  --table-name terraform-locks-dev \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1

# Prod state bucket + lock table
aws s3api create-bucket \
  --bucket devops-portfolio-tfstate-prod \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket devops-portfolio-tfstate-prod \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket devops-portfolio-tfstate-prod \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws dynamodb create-table \
  --table-name terraform-locks-prod \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

Verify:

```bash
aws s3 ls | grep devops-portfolio-tfstate
aws dynamodb list-tables | grep terraform-locks
```

---

## Step 2: Create EC2 Key Pairs

```bash
# Dev key pair
aws ec2 create-key-pair \
  --key-name devops-portfolio-dev \
  --query 'KeyMaterial' \
  --output text > devops-portfolio-dev.pem

# Prod key pair
aws ec2 create-key-pair \
  --key-name devops-portfolio-prod \
  --query 'KeyMaterial' \
  --output text > devops-portfolio-prod.pem

# Secure the files
chmod 400 devops-portfolio-dev.pem devops-portfolio-prod.pem
```

---

## Step 3: Register Repo in GitLab

1. Go to gitlab.com > New Project > Import project > GitHub
2. Import your `devops-portfolio-projects` repo (or create blank and push)
3. Note the project URL for CI/CD configuration

---

## Step 4: Configure GitLab CI/CD Variables

Go to your GitLab repo > Settings > CI/CD > Variables. Add:

| Variable | Value | Protected | Masked |
|----------|-------|-----------|--------|
| `AWS_ACCESS_KEY_ID` | Your IAM access key | Yes | Yes |
| `AWS_SECRET_ACCESS_KEY` | Your IAM secret key | Yes | Yes |
| `AWS_DEFAULT_REGION` | us-east-1 | Yes | No |

Ensure you have a GitLab Runner registered:

```bash
# Install GitLab Runner (on a dedicated machine or VM)
curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | sudo bash
sudo apt-get install gitlab-runner

# Register the runner
sudo gitlab-runner register \
  --url https://gitlab.com/ \
  --registration-token YOUR_TOKEN \
  --executor docker \
  --docker-image hashicorp/terraform:1.6
```

---

## Step 5: Update tfvars with Real Values

Edit `environments/dev.tfvars` and `environments/prod.tfvars`:

```bash
# Add your public IP for SSH access (find it at https://checkip.amazonaws.com)
MY_IP=$(curl -s https://checkip.amazonaws.com)
echo "allowed_ssh_cidrs = [\"${MY_IP}/32\"]"

# Update key_name if you used different names
# Update instance_type based on your needs
# Update region if not us-east-1
```

The current tfvars files are already configured. Just ensure `key_name` matches what you created in Step 2.

---

## Step 6: Push to Trigger Pipeline

```bash
git add .
git commit -m "chore: terraform infrastructure configuration"
git push origin main
```

The GitLab CI pipeline will run automatically.

---

## Step 7: Verify Terraform Plan

The pipeline runs `terraform plan` on every push. Check in GitLab > CI/CD > Pipelines:

1. **validate** stage: `terraform fmt -check` and `terraform validate`
2. **plan** stage: `terraform plan` with the appropriate tfvars
3. **security** stage: `tfsec` security scan

View the plan output in the job artifacts or pipeline logs.

---

## Step 8: Manual Apply on Dev

1. Push to the `develop` branch (or create a merge request to develop)
2. The `apply-dev` job will be available for manual trigger
3. Go to CI/CD > Pipelines > click the play button on `apply-dev`

```bash
# Or apply locally (ensure you have AWS credentials configured)
cd terraform
terraform init -backend-config="../backends/dev.hcl"
terraform apply -var-file="../environments/dev.tfvars"
```

Verify:

```bash
terraform state list
# Should show: module.vpc.*, module.iam.*, module.compute.*
```

---

## Step 9: Promote to Prod

1. Merge develop into main
2. The `apply-prod` job requires manual approval
3. Go to CI/CD > Pipelines > click the play button on `apply-prod`

```bash
# Or apply locally
cd terraform
terraform init -backend-config="../backends/prod.hcl"
terraform apply -var-file="../environments/prod.tfvars"
```

Verify:

```bash
aws ec2 describe-instances --filters "Name=tag:Environment,Values=prod"
```

---

## Verification Checklist

```bash
# Dev environment
terraform state list -backend-config="../backends/dev.hcl" -var-file="../environments/dev.tfvars"
aws ec2 describe-instances --filters "Name=tag:Environment,Values=dev"

# Prod environment
terraform state list -backend-config="../backends/prod.hcl" -var-file="../environments/prod.tfvars"
aws ec2 describe-instances --filters "Name=tag:Environment,Values=prod"

# Check state locking
aws dynamodb get-item --table-name terraform-locks-dev --key '{"LockID":{"S":"devops-portfolio-tfstate-dev/terraform.tfstate"}}'
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| State lock error | `terraform force-unlock <LOCK_ID>` (use cautiously) |
| Runner can't pull Docker image | Check runner config: `sudo gitlab-runner verify` |
| tfsec finds critical issues | Review and fix before applying; tfsec exits non-zero on findings |
| Plan shows unexpected changes | Review tfvars; check if resources were modified outside Terraform |
| Apply fails with IAM errors | Verify the IAM user/role has sufficient permissions |

---

## Cleanup

```bash
# Destroy all infrastructure
cd terraform
terraform destroy -backend-config="../backends/dev.hcl" -var-file="../environments/dev.tfvars"
terraform destroy -backend-config="../backends/prod.hcl" -var-file="../environments/prod.tfvars"

# Remove state buckets (WARNING: destroys all state history)
aws s3 rb s3://devops-portfolio-tfstate-dev --force
aws s3 rb s3://devops-portfolio-tfstate-prod --force
aws dynamodb delete-table --table-name terraform-locks-dev
aws dynamodb delete-table --table-name terraform-locks-prod

# Delete key pairs
aws ec2 delete-key-pair --key-name devops-portfolio-dev
aws ec2 delete-key-pair --key-name devops-portfolio-prod
rm -f devops-portfolio-dev.pem devops-portfolio-prod.pem
```
