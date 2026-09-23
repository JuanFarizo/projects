package com.fari.metrics;

import java.util.List;
import java.util.Map;

public record ThreadSnapshot(
        int live,
        int daemon,
        int peak,
        long started,
        Map<Thread.State, Integer> stateCounts,
        List<DeadlockedThread> deadlockedThreads,
        List<ThreadCpuStat> topCpuThreads
) {
    public static ThreadSnapshot empty() {
        return new ThreadSnapshot(0, 0, 0, 0, Map.of(), List.of(), List.of());
    }
}
