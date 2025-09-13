package exercism.collatz;

import org.openjdk.jmh.annotations.*;

import java.util.concurrent.TimeUnit;

@State(Scope.Thread)
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.NANOSECONDS)
public class CollatzCalculatorRecursiveBenchmark {

    private CollatzCalculatorRecursive collatzCalculatorRecursive;

    @Setup
    public void setup() {
        collatzCalculatorRecursive = new CollatzCalculatorRecursive();
    }

    @Benchmark
    public void computeStepCount() {
        collatzCalculatorRecursive.computeStepCount(1000);
    }
}
