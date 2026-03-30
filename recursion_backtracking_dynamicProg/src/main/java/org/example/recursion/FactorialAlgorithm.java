package org.example.recursion;

public class FactorialAlgorithm {
    // We have to return the values, otherwise we are not able to get
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

    static int recursiveCollatzCalculator(int start, int step) {
        // (x & 1) == 1); // true   ->  impar
        // (x & 1) == 1); // false  ->  par
        //Base Case 
        if(start == 1) return step;
        return recursiveCollatzCalculator((start & 1 ) == 1 ? (start * 3 + 1): start >> 1, ++step);
    }

    public static void main(String[] args) {
        System.out.println(recursiveCollatzCalculator(12, 0));
    }


    // (4, 1)
    // Tail(4 - 1, 4 * 1 )
    // Tail(3 - 1, 3 * 4 )
    // Tail(2 - 1, 2 * 12 )
    // n = 1 y return acc=24.
}
