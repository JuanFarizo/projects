package org.example.proxy;

import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.HashMap;
import java.util.Map;

interface Human {
    void walk();

    void talk();
}

class PersonProxy implements Human {

    @Override
    public void walk() {
        System.out.println("Im walking");
    }

    @Override
    public void talk() {
        System.out.println("Im talking");
    }

}

// Dynamic proxy which takes an existing object of type person and counts the
// number of methods inside person that have actually been called.
class LoggingHandler implements InvocationHandler {
    private final Object target;
    private final Map<String, Integer> calls = new HashMap<>();

    public LoggingHandler(Object target) {
        this.target = target;
    }

    @Override
    public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
        String name = method.getName();
        if (name.contains("toString")) {
            return calls.toString();
        }

        calls.merge(name, 1, Integer::sum);
        return method.invoke(target, args);
    }

}

public class DynamicProxyDemo {
    // utility method here for constructing a dynamic proxy with logging on any kind
    // of object.
    // Target, which is the object for which the logging is required, and
    // we're going to specify as a class of T the interface
    // We actually want to get a particular interface and a dynamic proxy for that
    // interface. So you cannot simply just take the underlying class and get that
    // as the end result because that wouldn't work.
    @SuppressWarnings("unchecked")
    public static <T> T withLogin(T target, Class<T> interfaceVar) {
        return (T) Proxy.newProxyInstance(
                interfaceVar.getClassLoader(),
                new Class<?>[] { interfaceVar },
                new LoggingHandler(target));
    }

    public static void main(String[] args) {
        PersonProxy personProxy = new PersonProxy();
        Human logged = withLogin(personProxy, Human.class);
        logged.talk();
        logged.walk();
        logged.walk();
        System.out.println(logged);
    }
}
