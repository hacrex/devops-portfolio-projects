FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY app/pom.xml .
RUN mvn dependency:go-offline -B
COPY app/src ./src
RUN mvn clean package -DskipTests

FROM eclipse-temurin:17-jre-jammy
RUN groupadd -r appuser && useradd -r -g appuser appuser
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
RUN chown -R appuser:appuser /app
USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/actuator/health || exit 1
ENTRYPOINT ["java", "-jar", "app.jar"]
