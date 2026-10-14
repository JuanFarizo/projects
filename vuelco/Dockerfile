FROM eclipse-temurin:25-jdk-alpine AS build
WORKDIR /app
COPY . .
RUN ./mvnw package -DskipTests

FROM eclipse-temurin:25-jdk-alpine
WORKDIR /app
COPY --from=build /app/target/vuelco-0.0.1-SNAPSHOT.jar app.jar
CMD ["java", "-jar", "app.jar"]
