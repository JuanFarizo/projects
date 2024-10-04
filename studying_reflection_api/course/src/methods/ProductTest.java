package methods;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class ProductTest {
    public static void main(String[] args) {
        testGetters(ClothingProduct.class);
        testSetters(ClothingProduct.class);
    }

    public static void testSetters(Class<?> dataClass) {
        List<Field> fields = getAllFields(dataClass);

        for (Field field : fields) {
            String setterName = "set" + capitalizeFirstLetter(field.getName());
            Method setterMethod;
            try {
                setterMethod = dataClass.getMethod(setterName, field.getType());
            } catch (NoSuchMethodException e) {
                throw new IllegalStateException(
                        String.format("Setter:  %s not found", setterName));
            }
            if (!setterMethod.getReturnType().equals(void.class)) {
                throw new IllegalStateException(
                        String.format("Setter method:  %s has tu return void", setterName));
            }
        }
    }

    private static List<Field> getAllFields(Class<?> clazz) {
        if (clazz == null || clazz.equals(Object.class)) {
            return Collections.emptyList();
        }
        Field[] currentClassFields = clazz.getDeclaredFields();
        List<Field> inheritedFields = getAllFields(clazz.getSuperclass());
        List<Field> allFields = new ArrayList<>();
        allFields.addAll(Arrays.asList(currentClassFields));
        allFields.addAll(inheritedFields);
        return allFields;
    }

    public static void testGetters(Class<?> dataClass) {
        List<Field> fields = getAllFields(dataClass);
        Map<String, Method> methodNameToMap = mapMethodNameToMethod(dataClass);

        for (Field field : fields) {
            String getterName = "get" + capitalizeFirstLetter(field.getName());
            if (!methodNameToMap.containsKey(getterName))
                throw new IllegalStateException(
                        String.format("Field %s doesn't have a getter method", field.getName()));

            Method getter = methodNameToMap.get(getterName);
            if (!getter.getReturnType().equals(field.getType()))
                throw new IllegalStateException(
                        String.format("Getter method : %s() has return type %s but expected %s",
                                getter.getName(),
                                getter.getReturnType().getName(),
                                field.getType().getName()));
            if (getter.getParameterCount() > 0)
                throw new IllegalStateException(String.format(
                        "Getter: %s has %d arguments", getterName, getter.getParameterCount()));
        }

    }

    private static String capitalizeFirstLetter(String name) {
        return name.substring(0, 1).toUpperCase().concat(name.substring(1));
    }

    private static Map<String, Method> mapMethodNameToMethod(Class<?> dataClass) {
        Method[] allMethods = dataClass.getMethods();
        Map<String, Method> methodNameToMethod = new HashMap<>();
        for (Method method : allMethods) {
            methodNameToMethod.put(method.getName(), method);
        }
        return methodNameToMethod;
    }
}
