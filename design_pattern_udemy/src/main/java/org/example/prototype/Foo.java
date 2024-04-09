package org.example.prototype;

import java.io.Serializable;

import org.apache.commons.lang3.SerializationUtils;

/**
 * Using Apache Serialization for make
 * a deep copy of an object
 */
public class Foo implements Serializable {
    public int stuff;
    public String algo;

    public Foo(int stuff, String algo) {
        this.stuff = stuff;
        this.algo = algo;
    }

    @Override
    public String toString() {
        return "Foo [stuff=" + stuff + ", algo=" + algo + "]";
    }

}

class DemoFoo {
    public static void main(String[] args) {
        Foo foo = new Foo(42, "Algo");
        Foo clone = SerializationUtils.roundtrip(foo);

        clone.algo = "xyz";
        System.out.println(foo);
        System.out.println(clone);

    }
}