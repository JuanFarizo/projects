package exercises;

import java.lang.reflect.Array;

public class Exercise4 {
    public static void main(String[] args) {
        int[] input = new int[] { 0, 10, 20, 30, 40 };
        System.out.println(getArrayElement(input, 3));
    }

    public static Object getArrayElement(Object array, int index) {
        // The index can be both positive, negative, and zero.
        int length = Array.getLength(array);
        if (index < 0) {
            return Array.get(array, length - 1);
        } else {
            return Array.get(array, index);
        }
    }
}
