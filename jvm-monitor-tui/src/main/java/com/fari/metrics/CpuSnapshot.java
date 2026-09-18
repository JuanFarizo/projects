package com.fari.metrics;

public record CpuSnapshot(
        double processLoad,
        double systemLoad,
        int cores,
        double rollingAvgPercent,
        long[] history
) {
    public static CpuSnapshot empty() {
        return new CpuSnapshot(0, 0, 0, 0, new long[0]);
    }
}
