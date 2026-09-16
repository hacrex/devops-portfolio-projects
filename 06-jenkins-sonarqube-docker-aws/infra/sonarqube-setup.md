# SonarQube Setup Guide

## Deployment Option: Docker on Separate EC2

Run SonarQube on a separate instance from Jenkins to isolate analysis load.

```bash
# EC2: t3.medium minimum (4 GB RAM required for SonarQube)
# Install Docker
sudo apt update && sudo apt install docker.io -y
sudo systemctl enable docker

# Increase vm.max_map_count (required by Elasticsearch inside SonarQube)
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf

# Run SonarQube
docker run -d --name sonarqube \
    -p 9000:9000 \
    -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
    -v sonarqube_data:/opt/sonarqube/data \
    -v sonarqube_extensions:/opt/sonarqube/extensions \
    -v sonarqube_logs:/opt/sonarqube/logs \
    --restart unless-stopped \
    sonarqube:9.9-community
```

## Security Group Rules

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 9000 | TCP | Jenkins EC2 security group only | SonarQube UI + API |

**Never expose SonarQube to the public internet.** Access via SSH tunnel if needed:
```bash
ssh -L 9000:localhost:9000 ec2-user@<sonarqube-ec2-ip>
```

## Initial Configuration

1. Access `http://<sonarqube-ip>:9000` (or via SSH tunnel)
2. Default credentials: `admin` / `admin` — change immediately
3. Generate an auth token: My Account > Security > Generate Tokens
4. Store the token in Jenkins Credentials Store as a Secret Text credential named `sonarqube-token`

## Quality Gate Configuration

### Create a Custom Quality Gate
1. Go to Quality Gates > Create New
2. Name it: `Portfolio Quality Gate`
3. Add conditions:
   - **New Code:**
     - Bugs: 0 new
     - Vulnerabilities: 0 new
     - Code Smells: 0 new
     - Coverage on New Code: >= 80%
     - Duplicated Lines on New Code: <= 3%
   - **Overall Code:**
     - Maintainability Rating: A
     - Reliability Rating: A

### Create a Custom Quality Profile
1. Go to Quality Profiles > Create
2. Name: `Portfolio Java Profile`
3. Copy from: `Sonar way` (default)
4. Activate additional rules for:
   - Security Hotspots review
   - Custom regex patterns for secrets detection

## Jenkins Integration

### Configure SonarQube Server in Jenkins
1. Manage Jenkins > Configure System > SonarQube servers
2. Add server:
   - **Name:** `sonarqube`
   - **Server URL:** `http://<sonarqube-ip>:9000`
   - **Server authentication token:** select `sonarqube-token` credential

### Install SonarQube Scanner
1. Manage Jenkins > Global Tool Configuration > SonarQube Scanner
2. Add SonarQube Scanner installation (auto-install)

## Useful API Calls

```bash
# Check quality gate status for a project
curl -u <token>: http://localhost:9000/api/qualitygates/project_status?projectKey=<project-key>

# Get project metrics
curl -u <token>: "http://localhost:9000/api/measures/component?component=<project-key>&metricKeys=bugs,vulnerabilities,code_smells,coverage,duplicated_lines_density"
```

## Maintenance

- **Disk space:** Monitor `/opt/sonarqube/data` — clean up old analysis data periodically
- **Updates:** Pull new Docker image and recreate container; data persists in volumes
- **Backup:** Snapshot the `sonarqube_data` volume regularly
