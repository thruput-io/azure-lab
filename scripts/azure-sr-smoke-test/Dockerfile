# Stage 1: Build the fat JAR
FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /build
COPY pom.xml .
# Download dependencies first (layer cache)
RUN mvn dependency:go-offline -q
COPY src ./src
RUN mvn package -q -DskipTests

# Stage 2: Minimal runtime image
FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=builder /build/target/azure-sr-smoke-test-1.0-SNAPSHOT.jar /app/smoke-test.jar

# Default: read config from /etc/kafka/client.properties
ENTRYPOINT ["java", "-jar", "/app/smoke-test.jar"]
CMD ["/etc/kafka/client.properties"]
