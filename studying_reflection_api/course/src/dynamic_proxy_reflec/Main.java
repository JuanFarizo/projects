package dynamic_proxy_reflec;

import java.lang.reflect.InvocationHandler;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;

import dynamic_proxy_reflec.external.DatabaseReader;
import dynamic_proxy_reflec.external.HttpClient;
import dynamic_proxy_reflec.external.impl.DatabaseReaderImpl;
import dynamic_proxy_reflec.external.impl.HttpClientImpl;

public class Main {
    public static void main(String[] args) throws InterruptedException {
        HttpClient client = createProxy(new HttpClientImpl());
        DatabaseReader databaseReader = createProxy(new DatabaseReaderImpl());
        useHttpClient(client);
        useDatabaseReader(databaseReader);
    }

    static void useHttpClient(HttpClient httpClient) {
        httpClient.initialize();
        String response = httpClient.sendRequest("some request");

        System.out.println(
                String.format("Http response is : %s", response));
    }

    static void useDatabaseReader(DatabaseReader databaseReader) throws InterruptedException {
        int countRowInTable = databaseReader.countRowInTable("GamesTable");
        System.out.println(String.format("There are %s rows in gamestable", countRowInTable));

        String[] data = databaseReader.readRow("SELECT * FROM GamesTable");
        System.out.println(String.format("Received %s", String.join(",", data)));
    }

    // Step 1: Create implementation of InvocationHandler
    static class TimeMeasuringProxyHandler implements InvocationHandler {
        private final Object originalObject;

        public TimeMeasuringProxyHandler(Object originalObject) {
            this.originalObject = originalObject;
        }

        @Override
        public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
            Object result;
            System.out.println(String.format("Measuring Proxy - Before Execution method : %s()", method.getName()));
            long startTime = System.currentTimeMillis();
            // If we want the proxy behave exactly the same as the object proxy we have to
            // handle properly the exception:
            try {
                result = method.invoke(originalObject, args);
            } catch (InvocationTargetException e) {
                throw e.getTargetException();
            }

            long endTime = System.currentTimeMillis();
            System.out.println(System.lineSeparator());
            System.out.println(
                    String.format("Measuring Proxy - After Execution method : %s() took %dms \n", method.getName(),
                            endTime - startTime));
            return result;
        }
    }

    // Step 2: Create an Dynamic Proxy Instance
    @SuppressWarnings("unchecked")
    static <T> T createProxy(Object originalObject) {
        Class<?>[] interfaces = originalObject.getClass().getInterfaces();
        TimeMeasuringProxyHandler timeMeasuringProxyHandler = new TimeMeasuringProxyHandler(originalObject);
        return (T) Proxy.newProxyInstance(originalObject.getClass().getClassLoader(), interfaces,
                timeMeasuringProxyHandler);
    }
}
