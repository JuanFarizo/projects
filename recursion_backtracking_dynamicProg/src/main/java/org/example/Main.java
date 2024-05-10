package org.example;

import org.example.recursion.FibonacciNumberAlgorithm;

public class Main {
    public static void main(String[] args) {
        long start = System.currentTimeMillis();
        int head = FibonacciNumberAlgorithm.head(8);
        System.out.println(" the value is " + head + " and took " + (System.currentTimeMillis() - start / 1000));
        start = System.currentTimeMillis();
        int tail = FibonacciNumberAlgorithm.tail(8, 0);
        System.out.println(" the value is " + tail + " and took " + (System.currentTimeMillis() - start / 1000));
    }
}