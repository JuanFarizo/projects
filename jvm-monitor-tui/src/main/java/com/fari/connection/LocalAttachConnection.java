package com.fari.connection;

import com.sun.tools.attach.VirtualMachine;

import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;
import java.io.IOException;

/** Attaches to a local JVM by PID and starts its local JMX management agent. */
public final class LocalAttachConnection implements ConnectionHandle {

    private final String label;
    private final VirtualMachine vm;
    private final JMXConnector connector;
    private final MBeanServerConnection mbeanServerConnection;

    public LocalAttachConnection(String pid, String displayName) {
        this.label = "PID " + pid + " (" + displayName + ")";
        try {
            this.vm = VirtualMachine.attach(pid);
            String address = vm.startLocalManagementAgent();
            this.connector = JMXConnectorFactory.connect(new JMXServiceURL(address));
            this.mbeanServerConnection = connector.getMBeanServerConnection();
        } catch (Exception e) {
            throw new ConnectionException("Failed to attach to process " + pid, e);
        }
    }

    @Override
    public MBeanServerConnection mbeanServerConnection() {
        return mbeanServerConnection;
    }

    @Override
    public boolean isAlive() {
        try {
            mbeanServerConnection.getMBeanCount();
            return true;
        } catch (IOException e) {
            return false;
        }
    }

    @Override
    public String label() {
        return label;
    }

    @Override
    public void close() {
        try {
            connector.close();
        } catch (IOException ignored) {
            // best-effort — target may already be gone
        }
        try {
            vm.detach();
        } catch (Exception ignored) {
            // best-effort
        }
    }
}
