package com.fari.metrics;

public record BufferPoolSnapshot(
        long count,
        long used,
        long capacity,
        // KB, 40-sample
        long[] usedHistory
) {
    public static BufferPoolSnapshot empty() {
        return new BufferPoolSnapshot(0, 0, 0, new long[0]);
    }
}
