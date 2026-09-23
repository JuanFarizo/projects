package com.fari.metrics;

public record GcPauseEvent(
        GcPauseAvailability availability,
        String gcName,
        String cause,
        boolean isFullGc,
        long durationMs,
        long timestampMillis
) {
    public static GcPauseEvent unavailable() {
        return new GcPauseEvent(GcPauseAvailability.UNAVAILABLE, "", "", false, 0, 0);
    }

    public static GcPauseEvent pendingFirstEvent() {
        return new GcPauseEvent(GcPauseAvailability.PENDING_FIRST_EVENT, "", "", false, 0, 0);
    }
}
