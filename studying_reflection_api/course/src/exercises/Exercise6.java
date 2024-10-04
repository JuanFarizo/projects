package exercises;

import java.lang.reflect.Method;
import java.util.List;
import java.util.stream.Collectors;
import java.util.stream.Stream;

public class Exercise6 {
    public static void main(String[] args) {

    }

    public void runTestSuite(Class<?> testClass) throws Throwable {
        Object testObject = testClass.getDeclaredConstructor().newInstance();
        Method[] declaredMethods = testClass.getDeclaredMethods();
        Method beforeClassMethod = findMethodByName(declaredMethods, "beforeClass");
        if (beforeClassMethod != null) {
            beforeClassMethod.invoke(null);
        }
        Method setUpMethod = findMethodByName(declaredMethods, "setupTest");
        List<Method> testMethods = findMethodsByPrefix(declaredMethods, "test");
        for (Method testMethod : testMethods) {
            if (setUpMethod != null) {
                setUpMethod.invoke(testObject);
            }
            testMethod.invoke(testObject);
        }

        Method afterClassMethod = findMethodByName(declaredMethods, "afterClass");
        if (afterClassMethod != null) {
            afterClassMethod.invoke(null);
        }
    }

    /**
     * Helper method to find a method by name
     * Returns null if a method with the given name does not exist
     */
    private Method findMethodByName(Method[] methods, String name) {
        return Stream.of(methods)
                .filter(m -> m.getName().equals(name) && m.getParameterCount() == 0 && m.getReturnType() == void.class)
                .findFirst()
                .orElseGet(() -> null);
    }

    /**
     * Helper method to find all the methods that start with the given prefix
     */
    private List<Method> findMethodsByPrefix(Method[] methods, String prefix) {
        return Stream.of(methods)
                .filter(m -> m.getName().startsWith(prefix) && m.getParameterCount() == 0
                        && m.getReturnType() == void.class)
                .collect(Collectors.toList());
    }
}
