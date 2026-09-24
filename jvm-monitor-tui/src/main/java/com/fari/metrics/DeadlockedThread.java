package com.fari.metrics;

/**
 * One thread in a deadlock cycle: the lock it's blocked on and who holds it.
 * Comes from the {@code ThreadInfo} already fetched for thread names — not
 * the separate, rejected lock-contention feature (docs/specs/metrics.md).
 */
public record DeadlockedThread(
        long threadId,
        String threadName,
        String lockClassName,
        String lockOwnerName
) {
}
