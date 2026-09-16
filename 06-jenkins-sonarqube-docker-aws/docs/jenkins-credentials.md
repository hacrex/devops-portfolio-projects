# Jenkins Credentials Reference

**WARNING:** This document describes what credentials exist and how they are scoped. It does NOT contain actual values.

## Credential Inventory

### 1. `sonarqube-token`
- **Type:** Secret Text
- **Purpose:** Authenticate Jenkins SonarQube Scanner plugin to SonarQube server
- **Scope:** Used in `SonarQube Analysis` pipeline stage only
- **Rotation:** Regenerate in SonarQube (My Account > Security) and update in Jenkins

### 2. `dockerhub-credentials`
- **Type:** Username with Password
- **Purpose:** Push Docker images to DockerHub registry
- **Scope:** Used in `Push to DockerHub` pipeline stage only
- **Rotation:** Regenerate DockerHub access token, update Jenkins credential
- **Note:** Uses access token, not account password

### 3. `ec2-deploy-key`
- **Type:** SSH Username with Private Key
- **Purpose:** SSH into target EC2 instance for deployment
- **Scope:** Used in `Deploy to EC2` pipeline stage only
- **User:** `ec2-user`
- **Rotation:** Generate new key pair, update on target EC2 and in Jenkins

### 4. `github-webhook-secret`
- **Type:** Secret Text
- **Purpose:** Validate incoming GitHub webhook payloads (HMAC signature verification)
- **Scope:** Configured in Jenkins GitHub plugin settings
- **Rotation:** Regenerate in GitHub webhook settings and update Jenkins

### 5. `slack-webhook-url`
- **Type:** Secret Text
- **Purpose:** Send build notifications to Slack channel
- **Scope:** Used in `post` section of Jenkinsfile
- **Rotation:** Regenerate in Slack app settings

## How Credentials Are Scoped

- Each credential is used in exactly one pipeline stage or post action
- Credentials are injected via `withCredentials` blocks, not global environment variables
- Jenkins Credentials Store encrypts values at rest
- Build logs print `****` for masked credentials — never echoed in plaintext

## Audit

- Review credential usage via: Manage Jenkins > Manage Credentials
- Check who has read access to each credential
- Review Jenkins audit log for credential access events
