package exercises;

import java.util.Arrays;
import java.util.List;

public class Exercise1 {
    private static final List<String> JDK_PACKAGE_PREFIXES = Arrays.asList("com.sun.", "java", "javax", "jdk",
            "org.w3c", "org.xml");

    // public static PopupTypeInfo createPopupTypeInfoFromClass(Class<?> inputClass)
    // {
    // PopupTypeInfo popupTypeInfo = new PopupTypeInfo();

    // popupTypeInfo.setPrimitive(inputClass.isPrimitive())
    // .setInterface(inputClass.isInterface())
    // .setEnum(inputClass.isEnum())
    // .setName(inputClass.getSimpleName())
    // .setJdk(isJdkClass(inputClass));

    // return popupTypeInfo;
    // }

    /*********** Helper Methods ***************/

    public static boolean isJdkClass(Class<?> inputClass) {
        String packageName = inputClass.getPackageName();

        /** Complete the code to assign a value to packageName **/

        return JDK_PACKAGE_PREFIXES.stream()
                .anyMatch(packagePrefix -> packageName.startsWith(packagePrefix));
    }

    public static void main(String[] args) {

    }

}