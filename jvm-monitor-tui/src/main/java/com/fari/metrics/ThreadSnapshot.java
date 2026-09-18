package com.fari.metrics;

import java.util.Map;

public record ThreadSnapshot(
        int live,
        int daemon,
        int peak,
        long started,
        Map<Thread.State, Integer> stateCounts
) {
    public static ThreadSnapshot empty() {
        return new ThreadSnapshot(0, 0, 0, 0, Map.of());
    }
}
