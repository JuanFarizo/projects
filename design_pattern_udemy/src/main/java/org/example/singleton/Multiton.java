package org.example.singleton;

import java.util.HashMap;

enum Subsystem {
    PRIMARY,
    AUXILIARY,
    FALLBACK
}

class Printer {
    private static int instanceCount = 0;

    private Printer() {
        instanceCount++;
        System.out.println("A total of: " + instanceCount + " insntance create so far");
    }

    // This allows us to have a printer per subsystem,
    // with this way we can restrict the numbers and type of printers that we want
    // to have in our system
    private static HashMap<Subsystem, Printer> instances = new HashMap<>();

    public static Printer get(Subsystem ss) {
        if (instances.containsKey(ss)) {
            return instances.get(ss);
        } // And allows us to implement lazy loading
        Printer instance = new Printer();
        instances.put(ss, instance);
        return instance;
    }
}

public class Multiton {
    public static void main(String[] args) {
        Printer main = Printer.get(Subsystem.PRIMARY);
        Printer aux = Printer.get(Subsystem.AUXILIARY);
        Printer aux2 = Printer.get(Subsystem.AUXILIARY);
    }
}
