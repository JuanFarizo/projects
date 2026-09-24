package com.fari.metrics;

import com.fari.connection.ConnectionHandle;

/**
 * Programmed to an abstraction, not to a concrete collection mechanism,
 * the default and only implementation right now is JMX polling;
 * a future JFR-based implementation must be able to drop in here
 * without UI or call-site changes.
 */
public interface MetricsSource extends AutoCloseable {

    /** Begins background polling. Must not block the caller. */
    void start(ConnectionHandle connection);

    /** Non-blocking read of the latest snapshot. Never null after {@link #start}. */
    MetricsSnapshot snapshot();

    /**
     * Blocking, on-demand class histogram fetch — walks the whole
     * heap/metaspace on the target JVM (safepoint-inducing), so callers must
     * invoke it off the render thread and never on a poll cadence. Never
     * throws; a fetch or parse failure comes back as
     * {@link ClassHistogramResult#unavailable}.
     */
    ClassHistogramResult fetchClassHistogram();

    @Override
    void close();
}
