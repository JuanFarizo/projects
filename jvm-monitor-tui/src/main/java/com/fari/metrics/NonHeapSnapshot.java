package com.fari.metrics;

public record NonHeapSnapshot(
        long used,
        long committed,
        long max,
        long codeCacheUsed,
        long compressedClassSpaceUsed
) {
    public static NonHeapSnapshot empty() {
        return new NonHeapSnapshot(0, 0, 0, 0, 0);
    }
}
