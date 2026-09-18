package com.fari.metrics;

import com.fari.connection.ConnectionHandle;

/**
 * Programmed to an abstraction, not to a concrete collection mechanism (per
 * architecture.md) — the default and only implementation right now is JMX
 * polling; a future JFR-based implementation must be able to drop in here
 * without UI or call-site changes.
 */
public interface MetricsSource extends AutoCloseable {

    /** Begins background polling. Must not block the caller. */
    void start(ConnectionHandle connection);

    /** Non-blocking read of the latest snapshot. Never null after {@link #start}. */
    MetricsSnapshot snapshot();

    @Override
    void close();
}
