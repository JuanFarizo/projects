package com.fari.metrics;

import java.util.List;

public record GcSnapshot(List<GcCollectorStat> collectors, GcPauseEvent lastPause, List<GcPauseEvent> pauseHistory) {
    public static GcSnapshot empty() {
        return new GcSnapshot(List.of(), GcPauseEvent.unavailable(), List.of());
    }
}
