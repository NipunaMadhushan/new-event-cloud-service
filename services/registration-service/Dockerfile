# ---- Build stage: compile the Ballerina package into a runnable fat jar ----
FROM ballerina/ballerina:2201.13.4 AS build
WORKDIR /build
COPY . .
RUN bal build

# ---- Runtime stage: just the JRE + the jar, no Ballerina toolchain ----
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /build/target/bin/registration_service.jar app.jar
EXPOSE 8083
ENTRYPOINT ["java", "-jar", "app.jar"]
