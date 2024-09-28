package exercises;

import java.lang.reflect.Array;
import java.util.ArrayList;
import java.util.List;

// ArrayFlattening
public class Exercise5 {
    public static <T> void main(String[] args) {
        // int[] result = contact(int.class, 1, 2, 3, new int[] { 4, 5, 6 }, 7);
        Object arrObject = Array.newInstance(String.class, 3);
        System.out.println(arrObject.getClass().getSimpleName());
    }

    public static <T> T concat(Class<?> type, Object... arguments) {
        if (arguments.length == 0) {
            return null;
        }
        List<Object> elements = new ArrayList<>();
        for (Object argument : arguments) {
            if (argument.getClass().isArray()) {
                int length = Array.getLength(argument);

                for (int i = 0; i < length; i++) {
                    elements.add(Array.get(argument, i));
                }
            } else {
                elements.add(argument);
            }
        }

        Object flattenedArray = Array.newInstance(type, elements.size());

        for (int i = 0; i < elements.size(); i++) {
            Array.set(flattenedArray, i, elements.get(i));
        }

        return (T) flattenedArray;
    }
}
