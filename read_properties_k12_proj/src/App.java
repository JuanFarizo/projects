import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.FileReader;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Consumer;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class App {
    private static final Pattern PROPERTY_PATTERN = Pattern.compile("\\$\\{([^}]+)}");
    private static final String LEARNX_DIRECTORY = "/home/farins/k12_projects/learnx/learnx-svc";
    private static final String AGGLOMERATION_DIRECTORY = "/home/farins/k12_projects/agglomeration/agglomeration-app";
    private static final String DEV_PROPERTIES_DIRECTORY = "/home/farins/projects/read_properties_k12_proj/src/resources/dev.properties";

    private static final String OUTPUT_FILE_DEV_PROP = "/home/farins/projects/read_properties_k12_proj/src/resources/output-dev.properties";
    private static final String OUTPUT_FILE_LEARNX_PROP = "/home/farins/projects/read_properties_k12_proj/src/resources/learnx-dev.properties";
    private static final String OUTPUT_FILE_AGGLO_PROP = "/home/farins/projects/read_properties_k12_proj/src/resources/agglo-dev.properties";

    private static Map<String, String> devProperties;
    private static Map<String, String> learnxValueProperties = new HashMap<>(500);
    private static final Set<String> propertiesNameApp = new HashSet<>();
    private static final Consumer<Map<String, String>> processDevProperties = new ProcessProperties();
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
            processDevProperties.accept(devProperties);
            // StringBuilder stringBuilder = new StringBuilder();
            // Populate the StringBuilder
            // devProperties.forEach((k, v) -> {
            // if (k.matches("\\d+")) {
            // stringBuilder.append(v).append(System.lineSeparator());
            // } else {
            // stringBuilder.append(
            // String.format("%s=%s", k, v)).append(System.lineSeparator());
            // }
            // });
            // writeContentToFile(OUTPUT_FILE_DEV_PROP, stringBuilder.toString());

            searchPropertiesInDirectory(Paths.get(LEARNX_DIRECTORY));
            propertiesNameApp.forEach(k -> {
                k = k.substring(2, k.length() - 1);
                String value = devProperties.get(k);
                if (value == null) {
                    String newKey = "learnx.".concat(k);
                    value = devProperties.get(newKey);
                }
                if (value != null) {
                    learnxValueProperties.put(k, value);
                } else {
                    learnxValueProperties.put(k, "unknown property");
                }
            });
            writeContentToFile(OUTPUT_FILE_LEARNX_PROP, parsePropertiesToString(learnxValueProperties).toString());
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    private static String retrySearchPropertyValue(String key) {
        int dotIndex = key.indexOf('.');
        if (dotIndex != -1) {
            return key.substring(dotIndex + 1);
        }
        return null;
    }

    private static StringBuilder parsePropertiesToString(Map<String, String> map) {
        StringBuilder stringBuilder = new StringBuilder();
        map.forEach((k, v) -> {
            stringBuilder.append(
                    String.format("%s=%s", k, v)).append(System.lineSeparator());
        });
        return stringBuilder;
    }

    private static void writeContentToFile(String filePath, String content) throws IOException {
        Path path = Paths.get(filePath);
        try (BufferedWriter writer = Files.newBufferedWriter(path)) {
            writer.write(content);
        }
    }

    // private static String plainProperty(String value) {
    // Matcher matcher = PROPERTY_PATTERN.matcher(value);
    // if (matcher.find()) {
    // String property = matcher.group(0);
    // String propValue = devProperties.get(property.substring(2, property.length()
    // - 1).toLowerCase());
    // if (PROPERTY_PATTERN.matcher(propValue).find()) {
    // String plainProperty = plainProperty(propValue);
    // return matcher.replaceAll(plainProperty);
    // }
    // if (propValue != null) {
    // return matcher.replaceAll(propValue);
    // } else {
    // return null;
    // }
    // }
    // return value;
    // }

    private static Map<String, String> readPropertiesFile(String filePath) throws IOException {
        Map<String, String> propertiesMap = new LinkedHashMap<>(5000);
        int counter = 0;

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
                } else {
                    // To save the break lines and comments in the
                    propertiesMap.put(String.valueOf(counter++), line);
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
                    if (property.matches(".*[A-Z].*") || !propertiesNameApp.add(property))
                        continue;
                    System.out.println(property + " - " + fileName + " - {" + propertiesNameApp.size() + "}");
                }
            }
        } catch (IOException e) {
            // System.err.println("Error reading file: " + filePath + " - " +
            // e.getMessage());
        }
    }
}
