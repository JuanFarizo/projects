package constructor;

import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationTargetException;
import java.util.Arrays;

public class Main {
    public static void main(String[] args)
            throws InstantiationException, IllegalAccessException, IllegalArgumentException, InvocationTargetException {
        // printConstructorData(Person.class);
        // printConstructorData(Address.class);
        Person person = createInstanceWithArgeumtns(Person.class, "Pepe Trueno");
        System.out.println(person);
    }

    public static <T> T createInstanceWithArgeumtns(Class<T> clazz, Object... args)
            throws InstantiationException, IllegalAccessException, IllegalArgumentException, InvocationTargetException {
        for (Constructor<?> constructor : clazz.getDeclaredConstructors()) {
            if (constructor.getParameterTypes().length == args.length) {
                return (T) constructor.newInstance(args);
            }
        }
        System.out.println("An appropriated constructor was not found");
        return null;
    }

    public static void printConstructorData(Class<?> clazz) {
        Constructor<?>[] declaredConstructors = clazz.getDeclaredConstructors();
        System.out.println(
                String.format("class %s has %d declared constructors",
                        clazz.getSimpleName(),
                        declaredConstructors.length));
        for (int i = 0; i < declaredConstructors.length; i++) {
            Class<?>[] parameters = declaredConstructors[i].getParameterTypes();
            Arrays.stream(parameters).map(Class::getSimpleName).forEach(System.out::println);
        }
    }

    public static class Person {
        private final Address address;
        private final String name;
        private final int age;

        @Override
        public String toString() {
            return "Person [address=" + address + ", name=" + name + ", age=" + age + "]";
        }

        public Person() {
            this.name = "anonymous";
            this.age = 0;
            this.address = null;
        }

        public Person(String name) {
            this.name = name;
            this.age = 0;
            this.address = null;
        }

        public Person(String name, int age) {
            this.name = name;
            this.age = age;
            this.address = null;
        }

        public Person(Address address, String name, int age) {
            this.address = address;
            this.name = name;
            this.age = age;
        }

    }

    public static class Address {
        private String street;
        private int number;

        public Address(String street, int number) {
            this.street = street;
            this.number = number;
        }

        @Override
        public String toString() {
            return "Address [street=" + street + ", number=" + number + "]";
        }

    }
}
