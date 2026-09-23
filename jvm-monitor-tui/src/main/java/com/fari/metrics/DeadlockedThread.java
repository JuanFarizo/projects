package com.fari.metrics;

/**
 * One thread in a detected deadlock cycle, with the lock it's blocked on and
 * who holds it. Sourced from {@code ThreadInfo.getLockInfo()}/{@code
 * getLockOwnerName()} on the same {@code getThreadInfo()} call already made
 * for the thread names — no extra JMX round-trip, no contention monitoring
 * flag (that's the separate, rejected "lock contention" feature — see
 * docs/spec/metrics.md).
 */
public record DeadlockedThread(
        long threadId,
        String threadName,
        String lockClassName,
        String lockOwnerName
) {
}
