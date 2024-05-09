package org.example.recursion;

public class Recursion {
    public static void head(int n) {
        if (n==0) return;
        // 1. Call the method recursively
        head(n -1);
        // 2. Backtracking phase when call the operations
        System.out.println("Head: the value n is: " + n);
    }

    public static void tail(int n) {
        if (n == 0) return;
        // 1. Do some operation
        System.out.println("Tail: the value n is: " + n);
        // 2. Call the method recursively
        tail(n - 1);
    }
}
