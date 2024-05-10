package org.example.recursion;

public class FibonacciNumberAlgorithm {
    public static int head(int n) {
        //Base case F(0)=0 and F(1)=1
        if(n == 0) return 0;
        if(n == 1) return 1;
        // Call the method(s) recursively
        int fib1 = head(n-1);
        int fib2 = head(n-2);
        //Java calculates the same values several times
        // This is why DYNAMIC PROGRAMMING eliminate this issue

        // Make some operations and return
        return fib1+fib2;
    }

    public static int tail(int n, int acc) {
        if(n == 0) return acc;
        if(n == 1) return acc + 1;

        int fib1 = tail(n - 1, acc);
        int fib2 = tail(n - 2, acc);
        acc = fib1 + fib2;
        return  acc;
    }
}
