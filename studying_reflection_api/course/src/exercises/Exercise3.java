package exercises;

import java.lang.reflect.Field;

public class Exercise3 {
    private static final long HEADER_SIZE = 12;
    private static final long REFERENCE_SIZE = 4;

    public static long sizeOfObject(Object input) throws IllegalArgumentException, IllegalAccessException {
        Field[] fields = input.getClass().getDeclaredFields();
        long size = HEADER_SIZE + REFERENCE_SIZE;
        for (Field field : fields) {
            field.setAccessible(true);
            if (field.isSynthetic())
                continue;

            if (field.getType().isPrimitive()) {
                size += sizeOfPrimitiveType(field.getType());
            } else if (field.getType().equals(String.class)) {
                size += sizeOfString(field.get(input).toString());
            }
        }
        return size;
    }

    public static void main(String[] args) throws IllegalArgumentException, IllegalAccessException {
        AccountSummary accountSummary = new AccountSummary("John", "Smith", (short) 20, 100_000);
        long asSize = sizeOfObject(accountSummary);
        System.out.println(asSize);

    }

    private static long sizeOfPrimitiveType(Class<?> primitiveType) {
        if (primitiveType.equals(int.class)) {
            return 4;
        } else if (primitiveType.equals(long.class)) {
            return 8;
        } else if (primitiveType.equals(float.class)) {
            return 4;
        } else if (primitiveType.equals(double.class)) {
            return 8;
        } else if (primitiveType.equals(byte.class)) {
            return 1;
        } else if (primitiveType.equals(short.class)) {
            return 2;
        }
        throw new IllegalArgumentException(String.format("Type: %s is not supported", primitiveType));
    }

    private static long sizeOfString(String inputString) {
        int stringBytesSize = inputString.getBytes().length;
        return HEADER_SIZE + REFERENCE_SIZE + stringBytesSize;
    }

    public static class AccountSummary {
        private final String firstName;
        private final String lastName;
        private final short age;
        private final int salary;

        public AccountSummary(String firstName, String lastName, short age, int salary) {
            this.firstName = firstName;
            this.lastName = lastName;
            this.age = age;
            this.salary = salary;
        }

    }
}
