package com.fari.metrics;

/**
 * Real state for GC last-pause data,"unavailable for this connection"
 * (connection method 5, SSH + jcmd/jstat, has no MBeanServerConnection)
 * must be modeled explicitly rather than left as anull/absent value.
 */
public enum GcPauseAvailability {
    /** Notification listener registered and at least one GC event captured. */
    AVAILABLE,
    /** Notification listener registered, but no GC event has fired yet. */
    PENDING_FIRST_EVENT,
    /** Connection method doesn't support JMX notifications (e.g. method 5). */
    UNAVAILABLE
}
