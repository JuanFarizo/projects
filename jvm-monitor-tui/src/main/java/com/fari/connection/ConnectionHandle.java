package com.fari.connection;

import javax.management.MBeanServerConnection;

/**
 * Abstraction the Metrics Layer depends on — never on a concrete transport
 * (VirtualMachine, SSH tunnel, Docker exec, ...).
 */
public interface ConnectionHandle extends AutoCloseable {

    MBeanServerConnection mbeanServerConnection();

    boolean isAlive();

    String label();

    @Override
    void close();
}
