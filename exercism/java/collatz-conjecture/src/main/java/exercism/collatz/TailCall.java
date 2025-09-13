package exercism.collatz;

import java.util.function.Supplier;

@FunctionalInterface
public interface TailCall<T> {

    T eval();

    default boolean isDone() {
        return true;
    }

    static <T> TailCall<T> done(T value) {
        return () -> value;
    }

    static <T> TailCall<T> call(Supplier<TailCall<T>> nextCall) {
        return new TailCall<T>() {
            @Override
            public T eval() {
                // This loop is the "trampoline"
                TailCall<T> current = this;
                while (!current.isDone()) {
                    current = current.get();
                }
                return current.eval();
            }

            @Override
            public boolean isDone() {
                return false;
            }
            
            private TailCall<T> get() {
                return nextCall.get();
            }
        };
    }
}
