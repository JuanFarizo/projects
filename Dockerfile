FROM eclipse-temurin:25-jdk-alpine

WORKDIR /app

# Copiamos solo tu proyecto principal (carpeta vuelco)
COPY ./vuelco /app

# Damos permisos al wrapper
RUN chmod +x mvnw

# Compilamos con Maven Wrapper
RUN ./mvnw package -DskipTests

# Ejecutamos el JAR generado
CMD ["java", "-jar", "target/vuelco-0.0.1-SNAPSHOT.jar"]
