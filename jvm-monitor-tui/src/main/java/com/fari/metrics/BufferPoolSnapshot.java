package com.fari.metrics;

public record BufferPoolSnapshot(
        long count,
        long used,
        long capacity
) {
    public static BufferPoolSnapshot empty() {
        return new BufferPoolSnapshot(0, 0, 0);
    }
}
