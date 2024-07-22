package com.thread_terminator;

import java.math.BigInteger;

public class ThreadTerminator {
  // Interrup a thread from an other thread
  public static void main(String[] args) {
    // Thread thread = new Thread(new BlockingThread());
    // thread.start();
    // thread.interrupt();

    Thread thread2 = new Thread(new LongComputationTask(new BigInteger("2"), new BigInteger("10")));
    thread2.setDaemon(true);
    thread2.start();
  }

  private static class BlockingThread implements Runnable {
    @Override
    public void run() {
      try {
        Thread.sleep(30000);
      } catch (InterruptedException e) {
        System.out.println("Exiting block thread");
      }
    }
  }

  private static class LongComputationTask implements Runnable {
    private BigInteger base;
    private BigInteger power;

    public LongComputationTask(BigInteger base, BigInteger power) {
      this.base = base;
      this.power = power;
    }

    @Override
    public void run() {
      System.out.println(base + "^" + power + " =" + pow(base, power));
    }
  }

  private static BigInteger pow(BigInteger base, BigInteger power) {
    BigInteger result = BigInteger.ONE;

    for (BigInteger i = BigInteger.ZERO; i.compareTo(power) != 0; i = i.add(BigInteger.ONE)) {
      if (Thread.currentThread().isInterrupted()) {
        System.out.println("Prematurely interrupted");
        return BigInteger.ZERO;
      }
      result = result.multiply(base);
    }
    return result;
  }
}
