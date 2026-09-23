package com.fari.connection;

import javax.management.MBeanServerConnection;

/**
 * Abstraction the Metrics Layer depends on — never on a concrete transport
 * (VirtualMachine, SSH tunnel, Docker exec, ...).
 */
public interface ConnectionHandle extends AutoCloseable {

    MBeanServerConnection mbeanServerConnection();

    /**
     * Whether this connection method supports JMX notifications (required for
     * the GC last-pause listener). True for every JMX-based method; false for
     * method 5 (SSH + jcmd/jstat), which has no MBeanServerConnection at all.
     */
    default boolean supportsGcNotifications() {
        return true;
    }

    boolean isAlive();

    String label();

    @Override
    void close();
}
