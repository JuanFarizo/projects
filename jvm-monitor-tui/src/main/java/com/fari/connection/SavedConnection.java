package com.fari.connection;

import java.util.UUID;

/**
 * A saved remote connection profile — see docs/specs/architecture.md's
 * "Saved-connection persistence" section for the format contract.
 * <p>
 * {@code id} is the stable identity used for edit/delete lookups — it never
 * changes even if alias/host/port are edited. {@code username} is {@code ""}
 * (never null) when the profile has no saved auth. There is deliberately no
 * password/passphrase field anywhere in this type — secrets are never
 * persisted. {@code sshKeyPath} is a file path, not a secret, so it's safe to
 * persist; {@code sshPort}/{@code rmiPort} are {@code 0} for non-SSH methods.
 */
public record SavedConnection(String id, String alias, String host, int port, String username, String method,
                               int sshPort, String sshKeyPath, int rmiPort) {

    /** Connection method tag for direct remote JMX (method 2). */
    public static final String METHOD_DIRECT_REMOTE_JMX = "DIRECT_REMOTE_JMX";

    /** Connection method tag for SSH -L tunnel (method 3). */
    public static final String METHOD_SSH_TUNNEL = "SSH_TUNNEL";

    /** Direct remote JMX convenience constructor — no SSH fields. */
    public SavedConnection(String id, String alias, String host, int port, String username, String method) {
        this(id, alias, host, port, username, method, 0, "", 0);
    }

    /** Creates a new direct remote JMX profile with a freshly generated id. */
    public SavedConnection(String alias, String host, int port, String username, String method) {
        this(UUID.randomUUID().toString(), alias, host, port, username, method);
    }

    /** Creates a new SSH tunnel profile with a freshly generated id. */
    public SavedConnection(String alias, String host, int port, String username, String method,
                            int sshPort, String sshKeyPath, int rmiPort) {
        this(UUID.randomUUID().toString(), alias, host, port, username, method, sshPort, sshKeyPath, rmiPort);
    }

    public boolean hasAuth() {
        return username != null && !username.isBlank();
    }

    public boolean isSshTunnel() {
        return METHOD_SSH_TUNNEL.equals(method);
    }
}
