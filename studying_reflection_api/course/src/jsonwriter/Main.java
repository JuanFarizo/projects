package jsonwriter;

import java.lang.reflect.Array;
import java.lang.reflect.Field;

import jsonwriter.data.Actor;
import jsonwriter.data.Movie;

public class Main {
    public static void main(String[] args) throws IllegalArgumentException, IllegalAccessException {
        Actor actor1 = new Actor("Rambo", new String[] { "Rambo 1", "Rambo 2", "Rambo 3" });
        Actor actor2 = new Actor("Arnold", new String[] { "Terminator 1", "Terminator 2", "Terminator 3" });

        Movie movie = new Movie("Ramboneitor",
                10.0f,
                new String[] { "Action", "CS-FI", "Tiritios" },
                new Actor[] { actor1, actor2 });
        String json = objectToJson(movie, 1);
        System.out.println(json);
    }

    public static String objectToJson(Object instance, int identSize)
            throws IllegalArgumentException, IllegalAccessException {
        Field[] fields = instance.getClass().getDeclaredFields();
        StringBuilder stringBuilder = new StringBuilder();
        stringBuilder.append(ident(identSize));
        stringBuilder.append("{");
        stringBuilder.append(System.lineSeparator());
        for (int i = 0; i < fields.length; i++) {
            Field field = fields[i];
            field.setAccessible(true);
            if (field.isSynthetic())
                continue;

            stringBuilder.append(ident(identSize + 1));
            stringBuilder.append(formatStringValue(field.getName()));
            stringBuilder.append(":");
            if (field.getType().isPrimitive()) {
                stringBuilder.append(formatPrivitiveValue(field.get(instance), field.getType()));
            } else if (field.getType().equals(String.class)) {
                stringBuilder.append(formatStringValue(field.get(instance).toString()));
            } else if (field.getType().isArray()) {
                stringBuilder.append(arrayTyoJson(field.get(instance), identSize + 1));
            } else {
                stringBuilder.append(objectToJson(field.get(instance), identSize + 1));
            }

            if (i != fields.length - 1) {
                stringBuilder.append(",");
            }
            stringBuilder.append(System.lineSeparator());
        }
        stringBuilder.append(ident(identSize));
        stringBuilder.append("}");
        return stringBuilder.toString();
    }

    private static Object arrayTyoJson(Object arrayInstance, int identSize)
            throws IllegalArgumentException, IllegalAccessException {
        StringBuilder builder = new StringBuilder();
        int arrayLength = Array.getLength(arrayInstance);
        Class<?> componentType = arrayInstance.getClass().getComponentType();

        builder.append("[");
        builder.append(System.lineSeparator());
        for (int i = 0; i < arrayLength; i++) {
            Object element = Array.get(arrayInstance, i);
            if (componentType.isPrimitive()) {
                builder.append(ident(identSize + 1));
                builder.append(formatPrivitiveValue(element, componentType));
            } else if (componentType.equals(String.class)) {
                builder.append(ident(identSize + 1));
                builder.append(formatStringValue(element.toString()));
            } else {
                builder.append(objectToJson(element, identSize + 1));
            }
            if (i != arrayLength - 1) {
                builder.append(", ");
            }
            builder.append(System.lineSeparator());
        }
        builder.append(ident(identSize));
        builder.append("]");
        return builder.toString();
    }

    private static String ident(int identSize) {
        StringBuilder builder = new StringBuilder();
        for (int i = 0; i < identSize; i++) {
            builder.append("\t");
        }
        return builder.toString();
    }

    private static String formatPrivitiveValue(Object instance, Class<?> type)
            throws IllegalArgumentException, IllegalAccessException {
        if (type.equals(boolean.class) ||
                type.equals(int.class) ||
                type.equals(long.class) ||
                type.equals(short.class)) {
            return instance.toString();
        } else if (type.equals(double.class) || type.equals(float.class)) {
            return String.format("%.02f", instance);
        }

        throw new RuntimeException(
                String.format("Type: %s is unsupported", type.getName()));
    }

    private static String formatStringValue(String value) {
        return String.format("\"%s\"", value);
    }
}
