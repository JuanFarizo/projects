package com.fari.metrics;

public record BuffersSnapshot(
        BufferPoolSnapshot direct,
        BufferPoolSnapshot mapped
) {
    public static BuffersSnapshot empty() {
        return new BuffersSnapshot(BufferPoolSnapshot.empty(), BufferPoolSnapshot.empty());
    }
}
