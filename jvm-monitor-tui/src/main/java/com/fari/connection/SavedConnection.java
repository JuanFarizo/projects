package com.fari.connection;

import java.util.UUID;

/**
 * A saved remote connection profile — see docs/specs/architecture.md's
 * "Saved-connection persistence" section for the format contract.
 * <p>
 * {@code id} is the stable identity used for edit/delete lookups — it never
 * changes even if alias/host/port are edited. {@code username} is {@code ""}
 * (never null) when the profile has no saved auth. There is deliberately no
 * password field anywhere in this type — passwords are never persisted.
 */
public record SavedConnection(String id, String alias, String host, int port, String username, String method) {

    /** Connection method tag for direct remote JMX (method 2). */
    public static final String METHOD_DIRECT_REMOTE_JMX = "DIRECT_REMOTE_JMX";

    /** Creates a new profile with a freshly generated id. */
    public SavedConnection(String alias, String host, int port, String username, String method) {
        this(UUID.randomUUID().toString(), alias, host, port, username, method);
    }

    public boolean hasAuth() {
        return username != null && !username.isBlank();
    }
}
