# syntax=docker/dockerfile:1
FROM maven:3.9.11-eclipse-temurin-17 AS build
WORKDIR /workspace
COPY pom.xml .
RUN mvn -B -ntp dependency:go-offline
COPY src src
RUN mvn -B -ntp test

FROM build AS package
RUN mvn -B -ntp -DskipTests package

FROM eclipse-temurin:17-jre-alpine AS runtime
RUN apk upgrade --no-cache \
    && addgroup -g 10001 app \
    && adduser -u 10001 -G app -D app
WORKDIR /opt/app
COPY --from=package --chown=app:app /workspace/target/simple-java-app-1.0.0.jar app.jar
USER app
EXPOSE 8080
ENTRYPOINT ["java","-jar","/opt/app/app.jar"]
