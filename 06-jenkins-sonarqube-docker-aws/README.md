# 6. Jenkins CI/CD — SonarQube, Docker, GitHub Webhooks on AWS

## Overview
The foundational project: a self-hosted Jenkins CI/CD pipeline running on AWS EC2, integrated with SonarQube for code quality and GitHub webhooks for automatic triggering, building and pushing Docker images. This is the project that proves you can stand up and administer a CI server yourself — not just click through a managed CI SaaS UI.

## Architecture
```
GitHub repo (webhook configured)
      │  (push event)
      ▼
Jenkins (EC2 instance, self-managed)
  ├─ Jenkins agent/executor pulls source
  ├─ Maven/npm/pip build + unit tests
  ├─ SonarQube analysis (separate EC2 instance or container)
  │     └─ Quality Gate webhook back to Jenkins (pass/fail)
  ├─ Docker build (Jenkins agent has Docker installed)
  ├─ Push image to DockerHub or ECR
  ▼
Deploy stage: docker run / docker-compose on a target EC2 (or ECS)
```

## Pipeline Stages
1. **Webhook trigger** — GitHub webhook configured to hit Jenkins' `/github-webhook/` endpoint on push.
2. **Source checkout** — Jenkins pulls the branch that triggered the build.
3. **Build & unit test** — language-appropriate build tool (Maven/Gradle/npm/pip) runs the test suite; pipeline fails on test failure.
4. **SonarQube analysis** — Jenkins SonarQube Scanner plugin sends code to SonarQube server; Jenkins waits on the Quality Gate webhook callback before proceeding (not just fire-and-forget).
5. **Docker build** — image built from the app's `Dockerfile`, tagged with build number/commit SHA.
6. **Push to registry** — DockerHub or ECR, with credentials stored in Jenkins Credentials Store (never plaintext in the Jenkinsfile).
7. **Deploy** — SSH into target EC2 (via Jenkins SSH plugin or `sshagent`) and run `docker run`/`docker-compose up -d` with the new image, or push to an ECS service.

## Tools Used
Jenkins (self-hosted on EC2), SonarQube (self-hosted, separate instance/container), Docker, DockerHub/ECR, GitHub webhooks, AWS EC2, Jenkins Credentials plugin.

## What to Build & Push to This Folder
- `Jenkinsfile` (declarative pipeline) with all stages above, including the `waitForQualityGate` step
- `infra/ec2-setup.md` — documented steps for provisioning the Jenkins EC2 instance: security group rules (which ports open to whom), Jenkins installation, plugin list installed
- `infra/sonarqube-setup.md` — how SonarQube was installed/configured, quality gate rules used
- `Dockerfile`
- `docs/jenkins-credentials.md` — what credentials exist in the Jenkins store and how they're scoped (without exposing actual values, obviously)
- Screenshot of a green pipeline run and the SonarQube quality gate result

## Interview Points

**What this project proves:** you can install, configure, and secure a self-managed CI server — the fundamentals that managed CI (GitHub Actions, GitLab CI) hides from you, which interviewers specifically probe for when a candidate has only ever used SaaS CI.

**Likely questions and how to answer them:**
- *"Why self-host Jenkins instead of using GitHub Actions?"* — Be honest: for a portfolio project, it's to demonstrate you understand what a managed CI service abstracts (server provisioning, plugin management, agent scaling, patching). In a real org, reasons to self-host include specific compliance/network requirements, existing Jenkins investment, or needing plugins/integrations GitHub Actions doesn't support.
- *"How did you secure the Jenkins EC2 instance?"* — Have specifics: security group restricting inbound to your IP or a VPN, Jenkins behind HTTPS (reverse proxy/ALB with a cert), not running Jenkins as root, credentials stored in Jenkins Credentials Store rather than environment variables in plaintext.
- *"What does `waitForQualityGate` actually do, and why not just run the SonarQube scan and move on?"* — SonarQube analysis is asynchronous; the scanner submits the analysis and SonarQube processes it server-side, then calls back. `waitForQualityGate` pauses the pipeline until that callback confirms pass/fail, so you don't deploy code that actually failed quality checks just because the scan step itself "succeeded" (it always looks like it succeeded — it just submitted the job).
- *"How do you manage Jenkins plugin updates and avoid breaking the pipeline?"* — Name a real practice: pin plugin versions, test updates in a non-production Jenkins instance first, or explain you learned this the hard way if a plugin update broke something during the build.
- *"What's your credential rotation story — if the DockerHub token leaked, what would you do?"* — Revoke/regenerate the token, update the Jenkins credential, and explain you'd audit Jenkins build logs for any accidental exposure.
- *"How would you scale this if you had 50 developers pushing constantly?"* — Jenkins agents/executors (distribute builds across multiple worker nodes), or migrate to Jenkins on Kubernetes with dynamic agent pods spun up per build.

**Weak spots to pre-empt:** if you ran Jenkins as a single instance with no agent separation (master doing all the work), acknowledge that's a single point of failure/bottleneck and say what a distributed setup would look like.

**Numbers/metrics to have ready:** EC2 instance size used and why, build duration, number of plugins installed, quality gate pass rate across your commits.
