package com.fari.metrics;

public record HeapSnapshot(
        long used,
        long committed,
        long max,
        long eden,
        long old,
        long survivor,
        long[] usedHistory,
        long[] committedHistory
) {
    public static HeapSnapshot empty() {
        return new HeapSnapshot(0, 0, 0, 0, 0, 0, new long[0], new long[0]);
    }
}
