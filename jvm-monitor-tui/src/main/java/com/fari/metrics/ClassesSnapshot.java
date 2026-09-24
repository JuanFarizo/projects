package com.fari.metrics;

public record ClassesSnapshot(
        long used,
        long committed,
        long loaded,
        long unloaded,
        long[] usedHistory,
        long[] committedHistory,
        // -1 means no ceiling reported (-XX:MaxMetaspaceSize unset, the common case).
        long metaspaceMax,
        // Classes newly loaded per poll tick — a churn/rate signal, not a raw
        // count, so dynamic-class generation (proxies, Groovy) shows as spikes.
        long[] loadedDeltaHistory
) {
    public static ClassesSnapshot empty() {
        return new ClassesSnapshot(0, 0, 0, 0, new long[0], new long[0], -1, new long[0]);
    }
}
