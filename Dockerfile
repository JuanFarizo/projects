FROM eclipse-temurin:25-jdk-alpine

WORKDIR /app

# Copiamos tu proyecto principal
COPY projects/vuelco /app

# Damos permisos de ejecución al wrapper
RUN chmod +x mvnw

# Compilamos con Maven Wrapper
RUN ./mvnw package -DskipTests

# Ejecutamos el JAR generado
CMD ["java", "-jar", "target/vuelco-0.0.1-SNAPSHOT.jar"]

