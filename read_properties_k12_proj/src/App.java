import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class App {
    private static final Pattern PROPERTY_PATTERN = Pattern.compile("\\$\\{([^}]+)}");
    private static final String LEARNX_DIRECTORY = "/home/farins/k12_projects/learnx/learnx-svc";
    private static final String AGGLOMERATION_DIRECTORY = "/home/farins/k12_projects/agglomeration/agglomeration-app";
    private static final String DEV_PROPERTIES_DIRECTORY = "/home/farins/projects/read_properties_k12_proj/src/resources/dev.properties";
    private static Map<String, String> devProperties;
    private static final Set<String> propertiesFound = new HashSet<>();
    private static final List<String> SKIP_LIST_FILES = List.of(
            "application-config.properties",
            "pom.xml",
            "testing-context.xml",
            "assembly.xml",
            "catalina.properties",
            "build.information");

    public static void main(String[] args) throws Exception {
        try {
            devProperties = readPropertiesFile(DEV_PROPERTIES_DIRECTORY);
            devProperties.forEach((k, v) -> {
                String newValue = plainProperty(v);
                if (newValue != null && !newValue.equals(v)) {
                    devProperties.replace(k, newValue);
                }
            });
            devProperties.forEach((k, v) -> System.out.println(
                    String.format("%s - %s", k, v)));
            // searchPropertiesInDirectory(Paths.get(AGGLOMERATION_DIRECTORY));
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    private static String plainProperty(String value) {
        Matcher matcher = PROPERTY_PATTERN.matcher(value);
        if (matcher.find()) {
            String property = matcher.group(0);
            String propValue = devProperties.get(property.substring(2, property.length() - 1).toLowerCase());
            if (PROPERTY_PATTERN.matcher(propValue).find()) {
                String plainProperty = plainProperty(propValue);
                return matcher.replaceAll(plainProperty);
            }
            if (propValue != null) {
                return matcher.replaceAll(propValue);
            } else {
                return null;
            }
        }
        return value;
    }

    private static Map<String, String> readPropertiesFile(String filePath) throws IOException {
        Map<String, String> propertiesMap = new HashMap<>();

        try (BufferedReader reader = new BufferedReader(new FileReader(filePath))) {
            String line;
            while ((line = reader.readLine()) != null) {
                // Trim whitespace and check if the line is not empty
                line = line.trim();
                if (!line.isEmpty() && line.contains("=")) {
                    String[] parts = line.split("=", 2); // Split only on the first '='
                    String propertyName = parts[0].trim().toLowerCase(); // Get the property name
                    String propertyValue = parts[1].trim(); // Get the property value

                    // Store in the map
                    propertiesMap.put(propertyName, propertyValue);
                }
            }
        }

        return propertiesMap;
    }

    private static void searchPropertiesInDirectory(Path path) throws IOException {
        // Recursively walk through the directory
        Files.walk(path)
                .filter(Files::isRegularFile) // Only process regular files
                .forEach(App::searchPropertiesInFile);
    }

    private static void searchPropertiesInFile(Path filePath) {
        try {
            List<String> lines = Files.readAllLines(filePath);
            for (String line : lines) {
                Matcher matcher = PROPERTY_PATTERN.matcher(line);
                String fileName = filePath.getFileName().toString();
                if (SKIP_LIST_FILES.contains(fileName))
                    continue;
                while (matcher.find()) {
                    // Extract the property name (without the ${ and })
                    String property = matcher.group(0); // This includes the ${ and }
                    if (property.matches(".*[A-Z].*") || !propertiesFound.add(property))
                        continue;
                    System.out.println(property + " - " + fileName + " - {" + propertiesFound.size() + "}");
                }
            }
        } catch (IOException e) {
            // System.err.println("Error reading file: " + filePath + " - " +
            // e.getMessage());
        }
    }
}
