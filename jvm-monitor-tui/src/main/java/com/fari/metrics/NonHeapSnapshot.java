package com.fari.metrics;

public record NonHeapSnapshot(
        long used,
        long committed,
        long max,
        long codeCacheUsed,
        long compressedClassSpaceUsed,
        // -1 means "no ceiling reported" (a segment's MemoryUsage.getMax() came
        // back undefined) — a real, displayable state, not missing data.
        long codeCacheMax
) {
    public static NonHeapSnapshot empty() {
        return new NonHeapSnapshot(0, 0, 0, 0, 0, -1);
    }
}
