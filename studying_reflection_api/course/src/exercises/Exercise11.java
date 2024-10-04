package exercises;

import java.io.IOException;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.Arrays;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class Exercise11 {
    public static void main(String[] args) {

    }

    @Retention(RetentionPolicy.RUNTIME)
    @Target(ElementType.METHOD)
    public @interface Cacheable {

    }

    static interface DatabaseReader {
        void connectToDatabase();

        @Cacheable
        String readCustomerIdByName(String firstName, String lastName) throws IOException;

        int countRowsInCustomersTable();

        void addCustomer(String id, String firstName, String lastName) throws IOException;

        @Cacheable
        Date readCustomerBirthday(String id);
    }

    static class CachingInvocationHandler implements InvocationHandler {

        /**
         * Map that maps from a method name to a method cache
         * Each cache is a map from a list of arguments to a method result
         */
        private final Map<String, Map<List<Object>, Object>> cache = new HashMap<>();

        /**
         * Add any additional member variables here
         */
        private final Object realObject;

        public CachingInvocationHandler(Object realObject) {
            this.realObject = realObject;
        }

        @Override
        public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
            if (isMethodCacheable(method) && isInCache(method, args)) {
                return getFromCache(method, args);
            }
            Object result;
            try {
                result = method.invoke(realObject, args);
                putInCache(method, args, result);
            } catch (InvocationTargetException e) {
                throw e.getTargetException();
            }
            return result;
        }

        boolean isMethodCacheable(Method method) {
            return method.isAnnotationPresent(Cacheable.class);
        }

        /******************************* Helper Methods **************************/

        private boolean isInCache(Method method, Object[] args) {
            if (!cache.containsKey(method.getName())) {
                return false;
            }
            List<Object> argumentsList = Arrays.asList(args);

            Map<List<Object>, Object> argumentsToReturnValue = cache.get(method.getName());

            return argumentsToReturnValue.containsKey(argumentsList);
        }

        private void putInCache(Method method, Object[] args, Object result) {
            if (!cache.containsKey(method.getName())) {
                cache.put(method.getName(), new HashMap<>());
            }
            List<Object> argumentsList = Arrays.asList(args);

            Map<List<Object>, Object> argumentsToReturnValue = cache.get(method.getName());

            argumentsToReturnValue.put(argumentsList, result);
        }

        private Object getFromCache(Method method, Object[] args) {
            if (!cache.containsKey(method.getName())) {
                throw new IllegalStateException(
                        String.format("Result of method: %s is not in the cache", method.getName()));
            }

            List<Object> argumentsList = Arrays.asList(args);

            Map<List<Object>, Object> argumentsToReturnValue = cache.get(method.getName());

            if (!argumentsToReturnValue.containsKey(argumentsList)) {
                throw new IllegalStateException(
                        String.format("Result of method: %s and arguments: %s is not in the cache",
                                method.getName(),
                                argumentsList));
            }

            return argumentsToReturnValue.get(argumentsList);
        }
    }
}
