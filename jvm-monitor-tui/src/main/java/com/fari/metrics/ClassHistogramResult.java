package com.fari.metrics;

import java.util.List;

/**
 * On-demand result of a {@code gcClassHistogram} fetch — never part of
 * {@link MetricsSnapshot}, which is only ever the last polled state.
 * {@code available=false} covers both a fetch failure (connection dropped)
 * and a parse failure (non-HotSpot-family output) — the TUI shows
 * {@code errorMessage} either way rather than distinguishing them.
 */
public record ClassHistogramResult(boolean available, String errorMessage, List<ClassHistogramEntry> entries) {

    public static ClassHistogramResult notLoaded() {
        return new ClassHistogramResult(false, null, List.of());
    }

    public static ClassHistogramResult unavailable(String errorMessage) {
        return new ClassHistogramResult(false, errorMessage, List.of());
    }

    public static ClassHistogramResult of(List<ClassHistogramEntry> entries) {
        return new ClassHistogramResult(true, null, entries);
    }
}
