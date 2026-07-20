# ---- Build stage: compile the Ballerina package into a runnable fat jar ----
FROM ballerina/ballerina:2201.13.4 AS build
WORKDIR /build
COPY . .
RUN bal build

# ---- Runtime stage: just the JRE + the jar, no Ballerina toolchain ----
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /build/target/bin/event_service.jar app.jar
COPY observability.toml observability.toml
ENV BAL_CONFIG_FILES=/app/observability.toml
EXPOSE 8081 9797
ENTRYPOINT ["java", "-jar", "app.jar"]
