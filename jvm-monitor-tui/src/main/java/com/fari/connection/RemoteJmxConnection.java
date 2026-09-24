package com.fari.connection;

import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;
import java.io.IOException;
import java.rmi.ConnectException;
import java.util.HashMap;
import java.util.Map;

/**
 * Direct remote JMX over RMI (connection method 2 — see
 * docs/specs/jvm-connection-methods.md). Target JVM must be started with
 * {@code -Dcom.sun.management.jmxremote.port=<port> -Dcom.sun.management.jmxremote.rmi.port=<port>
 * -Djava.rmi.server.hostname=<reachable IP>}.
 */
public final class RemoteJmxConnection implements ConnectionHandle {

    private final String label;
    private final JMXConnector connector;
    private final MBeanServerConnection mbeanServerConnection;

    public RemoteJmxConnection(String host, int port, String username, String password, String alias) {
        this.label = alias + " (" + host + ":" + port + ")";
        try {
            JMXServiceURL url = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://" + host + ":" + port + "/jmxrmi");
            Map<String, Object> env = new HashMap<>();
            if (username != null && !username.isBlank()) {
                env.put(JMXConnector.CREDENTIALS, new String[]{username, password});
            }
            this.connector = JMXConnectorFactory.connect(url, env);
            this.mbeanServerConnection = connector.getMBeanServerConnection();
        } catch (SecurityException e) {
            throw new ConnectionException("Authentication failed for " + host + ":" + port, e);
        } catch (Exception e) {
            if (e instanceof ConnectException || e.getCause() instanceof ConnectException) {
                throw new ConnectionException("Could not reach " + host + ":" + port + " — connection refused", e);
            }
            throw new ConnectionException("Failed to connect to " + host + ":" + port, e);
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
    }
}
