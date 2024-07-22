package com.coordination;

import java.math.BigInteger;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public class ThreadCoordination {
    public static void main(String[] args) {
        List<Long> inputNumbers = Arrays.asList(999999L, 20L, 33L, 224L, 46L, 35L, 55L);
        List<FactorialThread> threads = new ArrayList<FactorialThread>();
        inputNumbers.forEach(number -> {
            FactorialThread factorialThread = new FactorialThread(number);
            threads.add(factorialThread);
        });
 
        for (FactorialThread factorialThread : threads) {
            factorialThread.start();
            try {
                factorialThread.join(200);
            } catch (InterruptedException e) {
                System.out.println("algo");
            }
        }

        for (FactorialThread thread : threads) {
            if (thread.isFinished()) {
                System.out.println("Factorial result: " + thread.getResult());
            } else {
                System.out.println("The calculation for is still in progress");
            }
        }

        try {
            Thread.currentThread().sleep(2000);
        } catch (Exception e) {
            // TODO: handle exception
        }

        for (FactorialThread factorialThread : threads) {
            System.out.println(factorialThread.getName() + " status: " + factorialThread.isAlive());
        }
    }

    public static class FactorialThread extends Thread {
        private long inputNumber;
        private BigInteger result = BigInteger.ZERO;
        private boolean isFinished = false;

        public FactorialThread(long inputNumber) {
            this.inputNumber = inputNumber;
        }

        @Override
        public void run() {
            this.result = factorial(inputNumber);
            this.isFinished = true;
        }

        private BigInteger factorial(long n) {
            BigInteger tempResult = BigInteger.ONE;
            for (long i = n; i > 0; i--) {
                if (Thread.currentThread().isInterrupted()) {
                    System.out.println("Is Interrupted");
                }
                tempResult = tempResult.multiply(new BigInteger(Long.toString(i)));
            }
            return tempResult;
        }

        public BigInteger getResult() {
            return result;
        }

        public boolean isFinished() {
            return isFinished;
        }
    }
}
