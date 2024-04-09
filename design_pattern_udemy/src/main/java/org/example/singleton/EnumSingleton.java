package org.example.singleton;

import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;

/**
 * Do not have the problem of thread safety
 * but the serialization do not preserver the
 * internal state of the singleton, only serialize
 * the name of the singleton
 */
enum EnumSingleton {
    INSTANCE;

    EnumSingleton() {
        value = 42;
    }

    private int value;

    public int getValue() {
        return value;
    }

    public void setValue(int value) {
        this.value = value;
    }

}

class DemoEnumSingleton {
    static void saveToFile(EnumSingleton bs, String filename) throws Exception {
        try (FileOutputStream fo = new FileOutputStream(filename);
                ObjectOutputStream out = new ObjectOutputStream(fo);) {
            out.writeObject(bs);
        }
    };

    static EnumSingleton readFromFile(String filename) throws Exception {
        try (FileInputStream fi = new FileInputStream(filename);
                ObjectInputStream in = new ObjectInputStream(fi);) {
            return (EnumSingleton) in.readObject();
        }
    }

    public static void main(String[] args) throws Exception {
        String filename = "myfile.bin";
        // EnumSingleton singleton = EnumSingleton.INSTANCE;
        // singleton.setValue(111);
        // saveToFile(singleton, filename);
        EnumSingleton singletonFromFile = readFromFile(filename);
        System.out.println(singletonFromFile.getValue());
    }
}
