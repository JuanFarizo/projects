FROM eclipse-temurin:25-jdk-alpine
WORKDIR /app
COPY . .
RUN mvn package -DskipTests
CMD ["java", "-jar", "target/vuelco-0.0.1-SNAPSHOT.jar"]