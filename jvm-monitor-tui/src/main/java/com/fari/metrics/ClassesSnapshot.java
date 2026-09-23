package com.fari.metrics;

public record ClassesSnapshot(
        long used,
        long committed,
        long loaded,
        long unloaded,
        long[] usedHistory,
        long[] committedHistory
) {
    public static ClassesSnapshot empty() {
        return new ClassesSnapshot(0, 0, 0, 0, new long[0], new long[0]);
    }
}
