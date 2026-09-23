package com.fari.metrics;

public record ThreadCpuStat(
        long threadId,
        String name,
        Thread.State state,
        long cpuTimeNanos
) {
}
