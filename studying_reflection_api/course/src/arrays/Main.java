package arrays;

import java.lang.reflect.Array;

public class Main {
    public static void main(String[] args) {
        String[] array = new String[] { "pepe", "trueno" };
        int[][] twoDimen = { { 1, 2 }, { 3, 4 } };
        inspectArrayValue(twoDimen);
    }

    public static void inspectArrayValue(Object arrayObject) {
        int length = Array.getLength(arrayObject);
        System.out.print("[");
        for (int i = 0; i < length; i++) {
            Object element = Array.get(arrayObject, i);
            if (element.getClass().isArray()) {
                inspectArrayValue(element);
            } else {
                System.out.print(element);
            }
            if (i != length - 1)
                System.out.print(", ");
        }
        System.out.print("]");
    }

    public static void inspectArrayObject(Object object) {
        Class<?> clazz = object.getClass();
        System.out.println(
                String.format("Is array : %s", clazz.isArray()));

        Class<?> arrayComponentType = clazz.getComponentType();

        System.out.println(
                String.format("This is an array of type: %s", arrayComponentType.getTypeName()));
    }
}
