# Sample Spring Boot Application

This is a minimal Spring Boot app used to demonstrate the Jenkins + SonarQube + Docker CI/CD pipeline.

## Endpoints

- `GET /` — Hello message
- `GET /actuator/health` — Health check (used by Docker HEALTHCHECK)

## Running Locally

```bash
mvn spring-boot:run
```

## Running with Docker

```bash
docker build -t netflix-clone:local .
docker run -p 8080:8080 netflix-clone:local
```
