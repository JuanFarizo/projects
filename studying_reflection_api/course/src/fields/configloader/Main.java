package fields.configloader;

import java.io.IOException;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Scanner;

import fields.data.GameConfig;
import fields.data.UserInterfaceConfig;

public class Main {
    private static final Path GAME_CONFIG_PATH = Paths.get("course/src/resources/game-properties.cfg");
    private static final Path USER_INTERFACE_PATH = Paths.get("course/src/resources/user-interface.cfg");

    public static void main(String[] args) throws IllegalArgumentException, IllegalAccessException,
            InstantiationException, InvocationTargetException, NoSuchMethodException, SecurityException, IOException {
        GameConfig config = createConfigObject(GameConfig.class, GAME_CONFIG_PATH);
        UserInterfaceConfig userConfig = createConfigObject(UserInterfaceConfig.class, USER_INTERFACE_PATH);
        System.out.println(config);
        System.out.println(userConfig);
        // System.out.println(Paths.);
    }

    public static <T> T createConfigObject(Class<T> clazz, Path filePath)
            throws IllegalArgumentException, IllegalAccessException, IOException, InstantiationException,
            InvocationTargetException, NoSuchMethodException, SecurityException {
        Scanner scanner = new Scanner(filePath);
        Constructor<?> constructor = clazz.getDeclaredConstructor();
        T configInstance = (T) constructor.newInstance();

        while (scanner.hasNextLine()) {
            String configLine = scanner.nextLine();
            String[] nameValuePair = configLine.split("=");
            String propertyName = nameValuePair[0];
            String propertyValue = nameValuePair[1];

            Field field;
            try {
                field = clazz.getDeclaredField(propertyName);
            } catch (Exception e) {
                System.out.println(
                        String.format("Property name: %s is unnsuported", propertyName));
                continue;
            }
            field.setAccessible(true);
            Object parsedValue = parseValue(field.getType(), propertyValue);
            field.set(configInstance, parsedValue);
        }
        scanner.close();
        return configInstance;
    }

    private static Object parseValue(Class<?> type, String propertyValue) {
        if (type.equals(int.class)) {
            return Integer.parseInt(propertyValue);
        } else if (type.equals(short.class)) {
            return Short.parseShort(propertyValue);
        } else if (type.equals(long.class)) {
            return Long.parseLong(propertyValue);
        } else if (type.equals(double.class)) {
            return Double.parseDouble(propertyValue);
        } else if (type.equals(float.class)) {
            return Float.parseFloat(propertyValue);
        } else if (type.equals(String.class)) {
            return propertyValue;
        }
        throw new RuntimeException(
                String.format("Type: %s unsupported", type.getName()));
    }
}
