package org.example.singleton;


//With this approach do not have to deal with thread safety
public class InnerStaticSingleton {
    private InnerStaticSingleton() {
    }

    private static class Impl {
        private static final InnerStaticSingleton INSTANCE = new InnerStaticSingleton();
    }

    public InnerStaticSingleton getInstance() {
        return Impl.INSTANCE;
    }
}
