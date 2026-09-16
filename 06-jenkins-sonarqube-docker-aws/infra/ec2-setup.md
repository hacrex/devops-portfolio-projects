# Jenkins EC2 Setup Guide

## Prerequisites
- AWS account with EC2 access
- Key pair for SSH access
- Security group configured

## EC2 Instance Configuration

### Instance Details
- **AMI:** Ubuntu 22.04 LTS
- **Instance Type:** t3.large (2 vCPU, 8 GB RAM minimum for Jenkins + builds)
- **Storage:** 50 GB GP3 (Jenkins build artifacts accumulate fast)

### Security Group Rules

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 22 | TCP | Your IP | SSH access |
| 8080 | TCP | Your IP / VPN | Jenkins UI |
| 50000 | TCP | Jenkins agents | Agent connections |

**Important:** Never expose port 8080 to 0.0.0.0/0. Use your IP or a VPN CIDR.

## Jenkins Installation

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Java 17
sudo apt install openjdk-17-jdk -y

# Add Jenkins repo key
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null

# Add Jenkins repo
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

# Install Jenkins
sudo apt update
sudo apt install jenkins -y

# Start and enable
sudo systemctl start jenkins
sudo systemctl enable jenkins

# Get initial admin password
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

## Required Plugins

Install via Manage Jenkins > Manage Plugins > Available:

- **Git** — source code checkout
- **GitHub Integration** — webhook trigger support
- **SonarQube Scanner** — code analysis
- **Docker Pipeline** — docker.build() / docker.push() steps
- **SSH Agent** — deploy via SSH
- **Credentials Binding** — secure credential management
- **Pipeline** — Jenkinsfile support
- **JUnit** — test result reporting
- **Slack Notification** — build status alerts

## GitHub Webhook Setup

1. Go to GitHub repo > Settings > Webhooks > Add webhook
2. **Payload URL:** `http://<JENKINS_PUBLIC_URL>/github-webhook/`
3. **Content type:** `application/json`
4. **Secret:** generate with `openssl rand -hex 20` and store in Jenkins credentials
5. **Events:** select "Just the push event" (or "Send everything" for PR triggers)

## Reverse Proxy (Optional but Recommended)

Use nginx to front Jenkins with HTTPS:

```nginx
server {
    listen 443 ssl;
    server_name jenkins.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/jenkins.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/jenkins.yourdomain.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_request_buffering off;
        proxy_buffering off;
    }
}
```

## Hardening Checklist

- [ ] Run Jenkins as non-root user (default `jenkins` user is fine)
- [ ] Restrict inbound to your IP or VPN only
- [ ] Enable HTTPS via reverse proxy or ALB
- [ ] Configure Jenkins CSRF protection (enabled by default)
- [ ] Disable Jenkins CLI over remoting (if not needed)
- [ ] Set up audit logging plugin
