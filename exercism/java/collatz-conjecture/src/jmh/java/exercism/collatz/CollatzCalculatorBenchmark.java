package exercism.collatz;

import org.openjdk.jmh.annotations.*;

import java.util.concurrent.TimeUnit;

@State(Scope.Thread)
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.NANOSECONDS)
public class CollatzCalculatorBenchmark {

    private CollatzCalculator collatzCalculator;

    @Setup
    public void setup() {
        collatzCalculator = new CollatzCalculator();
    }

    @Benchmark
    public void computeStepCount() {
        collatzCalculator.computeStepCount(1000);
    }
}
