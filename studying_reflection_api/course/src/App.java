import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class App {
    public static void main(String[] args) throws Exception {
        Class<String> stringClass = String.class;
        Map<String, Integer> mapObjct = new HashMap<>();
        Class<?> hashMapClass = mapObjct.getClass();
        Class<?> squareClass = Square.class;
        // printClassInfo(stringClass, hashMapClass, squareClass);
        // printClassInfo(Collection.class, boolean.class, int[][].class);
        
    }

    private static void printClassInfo(Class<?>... classes) {
        for (Class<?> clazz : classes) {
            System.out.println(
                    String.format(
                            "class name : %s, class package name: %s",
                            clazz.getSimpleName(),
                            clazz.getPackageName()));
            Class<?>[] implementedInterfaces = clazz.getInterfaces();
            for (Class<?> implInterfaceClass : implementedInterfaces) {
                System.out.println(String.format(
                        "Class %s implements: %s",
                        clazz.getSimpleName(),
                        implInterfaceClass.getSimpleName()));
            }
            System.out.println("Is array: " + clazz.isArray());
            System.out.println("Is primitive: " + clazz.isPrimitive());
            System.out.println("Is enum: " + clazz.isEnum());
            System.out.println("Is annonymous: " + clazz.isAnonymousClass());

            System.out.println();
            System.out.println();
        }
    }

    private static class Square implements Drawable {

        @Override
        public int getNumberOfCorners() {
            return 4;
        }

    }

    private static interface Drawable {
        int getNumberOfCorners();
    }

    private enum Color {
        BLUE, RED, GREEN
    }
}
