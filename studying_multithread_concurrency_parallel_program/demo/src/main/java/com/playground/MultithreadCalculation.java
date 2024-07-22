package com.playground;

import java.math.BigInteger;

public class MultithreadCalculation {
    public static void main(String[] args) throws InterruptedException {
        ComplexCalculation complexCalculation = new ComplexCalculation();
        BigInteger calculateResult = complexCalculation.calculateResult(new BigInteger("2"), new BigInteger("3"),
                new BigInteger("4"), new BigInteger("5"));
        System.out.println(calculateResult);
    }

    public static class ComplexCalculation {
        public BigInteger calculateResult(BigInteger base1, BigInteger power1, BigInteger base2, BigInteger power2)
                throws InterruptedException {
            BigInteger result;
            PowerCalculatingThread thread1 = new PowerCalculatingThread(base1, power1);
            PowerCalculatingThread thread2 = new PowerCalculatingThread(base2, power2);
            thread1.start();
            thread1.join();
            thread2.start();
            thread2.join();
            result = thread1.getResult().add(thread2.getResult());
            return result;
        }
    }

    private static class PowerCalculatingThread extends Thread {
        private BigInteger result = BigInteger.ONE;
        private BigInteger base;
        private BigInteger power;

        public PowerCalculatingThread(BigInteger base, BigInteger power) {
            this.base = base;
            this.power = power;
        }

        @Override
        public void run() {
            result = base.pow(Integer.valueOf(power.toString()));
        }

        public BigInteger getResult() {
            return result;
        }
    }
}
