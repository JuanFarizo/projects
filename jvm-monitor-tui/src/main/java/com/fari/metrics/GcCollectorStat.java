package com.fari.metrics;

public record GcCollectorStat(String name, long count, long totalTimeMs, double avgPauseMs) {
}
