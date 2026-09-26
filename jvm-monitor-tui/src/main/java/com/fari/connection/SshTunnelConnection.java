package com.fari.connection;

import com.jcraft.jsch.JSch;
import com.jcraft.jsch.JSchException;
import com.jcraft.jsch.Session;

import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;
import java.io.IOException;
import java.nio.file.Path;

/**
 * SSH -L tunnel (connection method 3 — see docs/specs/jvm-connection-methods.md).
 * Forwards {@code localhost:jmxPort} and {@code localhost:rmiPort} through the
 * SSH session to the same port numbers on the target's loopback — they must
 * match what the target JVM was started with ({@code jmxremote.port=<jmxPort>
 * jmxremote.rmi.port=<rmiPort> -Djava.rmi.server.hostname=localhost}), since
 * the RMI stub the target hands back says "reconnect to localhost:<rmiPort>",
 * which only resolves through this same tunnel.
 * <p>
 * Host key verification is strict against the user's own
 * {@code ~/.ssh/known_hosts} — same trust store their {@code ssh} CLI
 * already uses. An unrecognized host fails with a message telling them to
 * {@code ssh} in manually once first, rather than prompting or trusting
 * blindly. Does not cover JMX-level auth
 * ({@code -Dcom.sun.management.jmxremote.authenticate=true}) — that's a
 * separate, optional layer on top, not implemented here.
 */
public final class SshTunnelConnection implements ConnectionHandle {

    private final String label;
    private final Session session;
    private final JMXConnector connector;
    private final MBeanServerConnection mbeanServerConnection;

    public SshTunnelConnection(String host, int sshPort, String sshUser, String sshPassword,
                                String sshKeyPath, String sshKeyPassphrase, int jmxPort, int rmiPort, String alias) {
        this.label = alias + " (ssh:" + host + ")";
        try {
            JSch jsch = new JSch();
            jsch.setKnownHosts(Path.of(System.getProperty("user.home"), ".ssh", "known_hosts").toString());// TODO: This applies only to Mac/Linux?
            if (sshKeyPath != null && !sshKeyPath.isBlank()) {
                jsch.addIdentity(sshKeyPath, blankToNull(sshKeyPassphrase));
            }
            session = jsch.getSession(sshUser, host, sshPort);
            if (sshPassword != null && !sshPassword.isBlank()) {
                session.setPassword(sshPassword);
            }
            session.setConfig("StrictHostKeyChecking", "yes");
            try {
                session.connect(10_000);
            } catch (JSchException e) {
                String msg = e.getMessage() == null ? "" : e.getMessage();
                if (msg.contains("UnknownHostKey") || msg.contains("reject HostKey") || msg.contains("HostKey has been changed")) {
                    throw new ConnectionException(
                            "Unknown SSH host " + host + " — run `ssh " + sshUser + "@" + host
                                    + "` once from a terminal to accept its host key, then retry.", e);
                }
                if (msg.contains("Auth fail") || msg.contains("Auth cancel")) {
                    throw new ConnectionException("SSH authentication failed for " + sshUser + "@" + host, e);
                }
                throw new ConnectionException("Could not reach " + host + ":" + sshPort + " over SSH", e);
            }

            session.setPortForwardingL(jmxPort, "localhost", jmxPort);
            session.setPortForwardingL(rmiPort, "localhost", rmiPort);

            JMXServiceURL url = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://localhost:" + jmxPort + "/jmxrmi");
            connector = JMXConnectorFactory.connect(url);
            mbeanServerConnection = connector.getMBeanServerConnection();
        } catch (ConnectionException e) {
            throw e;
        } catch (Exception e) {
            throw new ConnectionException("Failed to establish SSH tunnel to " + host, e);
        }
    }

    private static String blankToNull(String s) {
        return (s == null || s.isBlank()) ? null : s;
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
        session.disconnect();
    }
}
