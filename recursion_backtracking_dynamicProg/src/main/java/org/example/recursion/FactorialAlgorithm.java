package org.example.recursion;

public class FactorialAlgorithm {
    //We have to return the values, otherwise we are not able to get
    // the result because these sub results are depending extremely
    // heavily on each other, stack frames are relying on each other

    public static long head(int n) {
        //Base case
        if (n == 1)
            return 1;
        // Call method recursively and some operation (n * result of the recursive call)
        return n * head(n - 1);
    }

    // tail recursive function calls are totally independent of each other.
    public static long tail(int n, long acc) {
        if (n == 1)
            return acc;
        return tail(n - 1, n * acc);
    }
}
