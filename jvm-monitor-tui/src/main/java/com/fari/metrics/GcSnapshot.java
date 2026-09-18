package com.fari.metrics;

import java.util.List;

public record GcSnapshot(List<GcCollectorStat> collectors) {
    public static GcSnapshot empty() {
        return new GcSnapshot(List.of());
    }
}
