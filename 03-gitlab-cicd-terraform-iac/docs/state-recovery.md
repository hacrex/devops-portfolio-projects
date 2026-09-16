# State Recovery Runbook

## Scenario 1: State File Corruption

### Detection
- `terraform plan` shows unexpected changes or errors
- State file is missing or contains invalid JSON

### Recovery Steps

1. **Check S3 versioning:**
   ```bash
   aws s3api list-object-versions \
     --bucket devops-portfolio-tfstate-prod \
     --prefix terraform.tfstate \
     --max-items 10
   ```

2. **Restore previous version:**
   ```bash
   aws s3api get-object \
     --bucket devops-portfolio-tfstate-prod \
     --key terraform.tfstate \
     --version-id "previous-version-id" \
     terraform.tfstate.restored
   ```

3. **Verify restored state:**
   ```bash
   terraform state pull --state=terraform.tfstate.restored
   ```

4. **Replace state:**
   ```bash
   aws s3 cp terraform.tfstate.restored s3://devops-portfolio-tfstate-prod/terraform.tfstate
   ```

## Scenario 2: Manual Console Changes (Drift)

### Detection
Run `terraform plan` — it will show resources that differ from state.

### Recovery Steps

1. **Import the manually changed resource:**
   ```bash
   terraform import aws_security_group.web sg-12345678
   ```

2. **Or revert manual changes:**
   ```bash
   terraform apply -var-file="environments/prod.tfvars"
   ```

3. **If the resource was deleted manually:**
   ```bash
   terraform state rm aws_instance.main
   terraform apply -var-file="environments/prod.tfvars"
   ```

## Scenario 3: State Lock Conflict

### Detection
`Error: Error locking state: Error acquiring the state lock`

### Resolution

1. **Check if another run is active:**
   ```bash
   aws dynamodb get-item \
     --table-name terraform-locks-prod \
     --key '{"LockID":{"S":"devops-portfolio-tfstate-prod/terraform.tfstate"}}'
   ```

2. **Force-unlock if confirmed safe:**
   ```bash
   terraform force-unlock LOCK_ID
   ```

## Prevention

- Always use remote state with DynamoDB locking
- Never run `terraform apply` locally outside CI
- Enable S3 versioning on state buckets
- Use separate state files per environment
- Review `terraform plan` output before every apply
