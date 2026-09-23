package com.fari.metrics;

/** Trivial long-lived JVM for JmxPollingMetricsSourceCollectionTest to attach to. */
public final class SleepyMain {
    public static void main(String[] args) throws InterruptedException {
        Thread.sleep(Long.MAX_VALUE);
    }
}
