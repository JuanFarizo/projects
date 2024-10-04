package methods.invocation;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Map.Entry;

import methods.invocation.database.DatabaseClient;
import methods.invocation.http.HttpClient;
import methods.invocation.logging.FileLogger;
import methods.invocation.udp.UdpClient;

public class Main {
    public static void main(String[] args) throws Throwable {
        DatabaseClient databaseClient = new DatabaseClient();
        HttpClient httpClient1 = new HttpClient("123.456.789.0");
        HttpClient httpClient2 = new HttpClient("11.33.55.0");
        FileLogger fileLogger = new FileLogger();
        UdpClient udpClient = new UdpClient();

        String requestBody = "request data";
        List<Class<?>> methodParametersTypes = Arrays.asList(new Class<?>[] { String.class });
        Map<Object, Method> requestExecutors = groupExecutors(
                Arrays.asList(databaseClient, httpClient1, httpClient2, fileLogger, udpClient),
                methodParametersTypes);
        executeAll(requestExecutors, requestBody);
    }

    public static void executeAll(Map<Object, Method> requestExecutors, String requestBody)
            throws Throwable {
        try {
            for (Entry<Object, Method> requestExecutorEntry : requestExecutors.entrySet()) {
                Object requestExecutor = requestExecutorEntry.getKey();
                Method method = requestExecutorEntry.getValue();
                Boolean invoResult = (Boolean) method.invoke(requestExecutor, requestBody);
                if (invoResult != null && !invoResult) {
                    System.out.println("Received negative result. Aborting ...");
                    return;
                }
            }
        } catch (InvocationTargetException e) {
            throw e.getTargetException();
        }
    }

    public static Map<Object, Method> groupExecutors(
            List<Object> requestExecutors,
            List<Class<?>> methodParameterTypes) {
        Map<Object, Method> instanceToMethod = new HashMap<>();
        for (Object requestExecutor : requestExecutors) {
            Method[] methods = requestExecutor.getClass().getDeclaredMethods();
            for (Method method : methods) {
                if (Arrays.asList(method.getParameterTypes()).equals(methodParameterTypes)) {
                    instanceToMethod.put(requestExecutor, method);
                }
            }
        }
        return instanceToMethod;
    }
}
