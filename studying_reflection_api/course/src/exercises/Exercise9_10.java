package exercises;

import java.lang.annotation.ElementType;
import java.lang.annotation.Repeatable;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public class Exercise9_10 {
    public static void main(String[] args) {

    }

    public static class User {
        String name;
        Role role;

        public User(String name, Role role) {
            this.name = name;
            this.role = role;
        }

        public Role getRole() {
            return role;
        }

    }

    public static enum Role {
        CLERK,
        MANAGER,
        SUPPORT_ENGINEER
    }

    public static enum OperationType {
        READ,
        WRITE,
        DELETE
    }

    public static class PermissionException extends Throwable {

    }

    /**
     * Checks that the logged-in user in the callerObject has the right permissions
     * to perform the operations
     * in the caller method.
     * Throws PermissionException if the user is not authorized to perform those
     * operations based on the user's
     * role
     */
    public static void checkPermissions(Object callerObject, String callerMethodName) throws Throwable {
        // DO NOT MODIFY THIS METHOD
        User user = getLoggedInUser(callerObject);
        Method callingMethod = getCallingMethod(callerObject, callerMethodName);
        Permissions[] allPermissions = getClassAnnotatedPermissions(callerObject);
        MethodOperations methodOperations = getCallerMethodOperations(callingMethod);

        OperationType[] methodOperationTypes = methodOperations.value();

        List<OperationType> userAllowedOperations = findUserAllowedOperations(allPermissions, user);

        for (OperationType methodOperationsTypes : methodOperationTypes) {
            if (!userAllowedOperations.contains(methodOperationsTypes)) {
                throw new PermissionException();
            }
        }
    }

    /**
     * Returns a List of all OperationTypes that the logged-in user is allowed to
     * perform
     * If the user has no permissions in the allPermissions, an empty list should be
     * returned
     */
    static List<OperationType> findUserAllowedOperations(Permissions[] allPermissions, User user) {
        Role role = user.getRole();
        List<OperationType> allowedOperations = new ArrayList<>();
        for (Permissions permissions : allPermissions) {
            if (permissions.role().equals(role)) {
                allowedOperations.addAll(Arrays.asList(permissions.allowed()));
                break;
            }
        }

        return allowedOperations;
    }

    /**
     * Returns all the Permissions annotations the the callerObject's class is
     * annotated with
     */
    static Permissions[] getClassAnnotatedPermissions(Object callerObject) {
        return callerObject.getClass().getAnnotationsByType(Permissions.class);
    }

    /**
     * Returns the MethodOperations annotation that the callerMethod is annotated
     * with
     */
    static MethodOperations getCallerMethodOperations(Method callerMethod) {
        return callerMethod.getAnnotation(MethodOperations.class);
    }

    // ********************* Helper Methods ******************************/

    /**
     * Returns the User object representing the logged-in user
     */
    private static User getLoggedInUser(Object callerObject) throws NoSuchFieldException, IllegalAccessException {
        // DO NOT MODIFY THIS METHOD
        Class<?> callerClass = callerObject.getClass();

        Field userField = callerClass.getDeclaredField("user");

        userField.setAccessible(true);

        if (!userField.getType().equals(User.class)) {
            throw new IllegalStateException("The caller object must have a user field of type User");
        }

        return (User) userField.get(callerObject);
    }

    /**
     * Returns the Method object of the callerObject's class corresponding to the
     * methodName
     */
    private static Method getCallingMethod(Object callerObject, String methodName) {
        // DO NOT MODIFY THIS METHOD
        return Arrays.stream(callerObject.getClass().getDeclaredMethods())
                .filter(method -> method.getName().equals(methodName))
                .findFirst()
                .orElseThrow(() -> new IllegalStateException(
                        String.format("The passed method name :%s does not exist", methodName)));
    }

    @Repeatable(Permission.class)
    @Target(ElementType.TYPE)
    public @interface Permissions {
        Role role();

        OperationType[] allowed();
    }

    @Retention(RetentionPolicy.RUNTIME)
    @Target(ElementType.TYPE)
    public @interface Permission {
        Permissions[] value();
    }

    @Retention(RetentionPolicy.RUNTIME)
    @Target(ElementType.METHOD)
    public @interface MethodOperations {
        OperationType[] value();
    }
}
