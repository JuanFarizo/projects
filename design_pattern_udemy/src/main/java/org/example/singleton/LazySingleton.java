package org.example.singleton;

public class LazySingleton {
    private static LazySingleton instance;

    private LazySingleton() {
        System.out.println("Initili a lazy singleton");
    }

    // public static LazySingleton getInstance() {
    // if (instance == null) {
    // instance = new LazySingleton();
    // }
    // return instance;
    // }

    // double checked locking
    public static LazySingleton getInstance() {
        if (instance == null) {
            synchronized (LazySingleton.class) {
                if (instance == null) {
                    instance = new LazySingleton();
                }
            }
        }
        return instance;
    }

}
