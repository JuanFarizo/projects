package exercism.collatz;

public class CollatzCalculatorRecursive {
    public int computeStepCount(int start) {
        if (start <= 0) {
            throw new IllegalArgumentException("Only positive integers are allowed");
        }
        return recursiveCollatzCalculator(start, 0).eval();
    }

    private TailCall<Integer> recursiveCollatzCalculator(int start, int step) {
        if (start == 1) {
            return TailCall.done(step);
        }
        return TailCall.call(() -> recursiveCollatzCalculator((start & 1) == 1 ? (start * 3 + 1) : start >> 1, ++step));
    }
}
