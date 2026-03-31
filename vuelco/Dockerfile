# Use Java 25 runtime
FROM eclipse-temurin:25-jdk-alpine

# Set working directory
WORKDIR /app

# Copy the JAR from Maven target folder
COPY target/vuelco-0.0.1-SNAPSHOT.jar app.jar

# Run the JAR
CMD ["java", "-jar", "app.jar"]
