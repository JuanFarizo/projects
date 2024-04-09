package org.example.singleton;

import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.io.Serializable;

public class BasicSingleton implements Serializable {
    private BasicSingleton() {

    }

    private static final BasicSingleton INSTANCE = new BasicSingleton();

    public static BasicSingleton getInstance() {
        return INSTANCE;
    }

    private int value = 0;

    public int getValue() {
        return value;
    }

    public void setValue(int value) {
        this.value = value;
    }

    protected Object readResolve() {
        return INSTANCE;
    }

}

class DemoBasicSingleton {
    static void saveToFile(BasicSingleton bs, String filename) throws Exception {
        try (FileOutputStream fo = new FileOutputStream(filename);
                ObjectOutputStream out = new ObjectOutputStream(fo);) {
            out.writeObject(bs);
        }
    };

    static BasicSingleton readFromFile(String filename) throws Exception {
        try (FileInputStream fi = new FileInputStream(filename);
                ObjectInputStream in = new ObjectInputStream(fi);) {
            return (BasicSingleton) in.readObject();
        }
    }

    public static void main(String[] args) throws Exception {
        BasicSingleton bs = BasicSingleton.getInstance();
        bs.setValue(111);
        String filename = "singleton.bin";
        saveToFile(bs, filename);
        bs.setValue(222);

        BasicSingleton bsFromFile = readFromFile(filename);
        System.out.println(bs == bsFromFile);
        System.out.println(bs.getValue());
        System.out.println(bsFromFile.getValue());
    }
}