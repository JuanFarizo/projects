package com.fari.ui;

import com.fari.connection.SavedConnection;
import dev.tamboui.toolkit.element.Element;

import static dev.tamboui.toolkit.Toolkit.*;

import java.util.ArrayList;

/**
 * Remote connect form — Direct Remote JMX (method 2) and SSH -L Tunnel
 * Hand-rolled
 * keyboard-driven form matching this codebase's existing manual-dispatch
 * convention (ConnectionsScreen's up/down+TableState), not TamboUI's
 * FormElement/FocusManager subsystem.
 * <p>
 * Doubles as the edit form for a saved connection ({@link #startEdit}) —
 * same fields, password/passphrase always start blank since they're never
 * persisted.
 */
public final class AddRemoteDialogScreen {

    public enum Field {
        ALIAS, HOST, METHOD, PORT, AUTH, USERNAME, PASSWORD,
        SSH_PORT, SSH_AUTH_TYPE, SSH_KEY_PATH, SSH_PASSPHRASE, RMI_PORT
    }

    public enum SshAuthType {
        PASSWORD, PRIVATE_KEY
    }

    /**
     * Result of a submitted form — passed as one object rather than growing the
     * callback's arg list further.
     */
    public record ConnectRequest(String alias, String host, int port, String username, String password,
            String method, int sshPort, String sshKeyPath, String sshPassphrase, int rmiPort) {
    }

    private Field focused = Field.ALIAS;
    private String alias = "";
    private String host = "";
    private String method = SavedConnection.METHOD_DIRECT_REMOTE_JMX;
    private String port = "";
    private boolean useAuth = false;
    private String username = "";
    private String password = "";
    private String sshPort = "22";
    private SshAuthType sshAuthType = SshAuthType.PASSWORD;
    private String sshKeyPath = "";
    private String sshPassphrase = "";
    private String rmiPort = "";
    private String validationError;
    private boolean editMode = false;
    private String editId;

    public void reset() {
        focused = Field.ALIAS;
        alias = "";
        host = "";
        method = SavedConnection.METHOD_DIRECT_REMOTE_JMX;
        port = "";
        useAuth = false;
        username = "";
        password = "";
        sshPort = "22";
        sshAuthType = SshAuthType.PASSWORD;
        sshKeyPath = "";
        sshPassphrase = "";
        rmiPort = "";
        validationError = null;
        editMode = false;
        editId = null;
    }

    /**
     * Prefills the form from an existing saved connection; password/passphrase stay
     * blank (never persisted).
     */
    public void startEdit(SavedConnection existing) {
        reset();
        focused = Field.ALIAS;
        alias = existing.alias();
        host = existing.host();
        method = existing.method();
        port = String.valueOf(existing.port());
        useAuth = existing.hasAuth();
        username = existing.username();
        password = "";
        sshPort = existing.sshPort() > 0 ? String.valueOf(existing.sshPort()) : "22";
        sshKeyPath = existing.sshKeyPath();
        sshAuthType = sshKeyPath != null && !sshKeyPath.isBlank() ? SshAuthType.PRIVATE_KEY : SshAuthType.PASSWORD;
        sshPassphrase = "";
        rmiPort = existing.rmiPort() > 0 ? String.valueOf(existing.rmiPort()) : "";
        validationError = null;
        editMode = true;
        editId = existing.id();
    }

    /**
     * Prefills the form like {@link #startEdit} but leaves edit mode off, so
     * submitting live-connects (and upserts) instead of only updating the
     * saved profile's metadata — used to re-collect the secrets an SSH
     * tunnel needs on every reconnect (password/passphrase are never saved).
     */
    public void startReconnect(SavedConnection existing) {
        startEdit(existing);
        editMode = false;
    }

    public boolean isEditMode() {
        return editMode;
    }

    public String editId() {
        return editId;
    }

    public Field focused() {
        return focused;
    }

    private boolean isSshTunnel() {
        return SavedConnection.METHOD_SSH_TUNNEL.equals(method);
    }

    private Field[] activeOrder() {
        if (isSshTunnel()) {
            var order = new ArrayList<Field>();
            order.add(Field.ALIAS);
            order.add(Field.HOST);
            order.add(Field.METHOD);
            order.add(Field.SSH_PORT);
            order.add(Field.USERNAME);
            order.add(Field.SSH_AUTH_TYPE);
            if (sshAuthType == SshAuthType.PASSWORD) {
                order.add(Field.PASSWORD);
            } else {
                order.add(Field.SSH_KEY_PATH);
                order.add(Field.SSH_PASSPHRASE);
            }
            order.add(Field.PORT);
            order.add(Field.RMI_PORT);
            return order.toArray(Field[]::new);
        }
        return useAuth
                ? new Field[] { Field.ALIAS, Field.HOST, Field.METHOD, Field.PORT, Field.AUTH, Field.USERNAME,
                        Field.PASSWORD }
                : new Field[] { Field.ALIAS, Field.HOST, Field.METHOD, Field.PORT, Field.AUTH };
    }

    /** True when Enter on the current field should submit rather than advance. */
    public boolean isOnLastField() {
        Field[] order = activeOrder();
        return order[order.length - 1] == focused;
    }

    public void focusNext() {
        Field[] order = activeOrder();
        int idx = indexOf(order, focused);
        focused = order[(idx + 1) % order.length];
    }

    public void focusPrevious() {
        Field[] order = activeOrder();
        int idx = indexOf(order, focused);
        focused = order[(idx - 1 + order.length) % order.length];
    }

    private static int indexOf(Field[] order, Field f) {
        for (int i = 0; i < order.length; i++) {
            if (order[i] == f) {
                return i;
            }
        }
        return 0;
    }

    public void toggleAuth() {
        if (focused == Field.AUTH) {
            useAuth = !useAuth;
        }
    }

    /**
     * Cycles Direct JMX / SSH Tunnel; resets focus onto the new field set's first
     * field.
     */
    public void toggleMethod() {
        if (focused == Field.METHOD) {
            method = isSshTunnel() ? SavedConnection.METHOD_DIRECT_REMOTE_JMX : SavedConnection.METHOD_SSH_TUNNEL;
        }
    }

    public void toggleSshAuthType() {
        if (focused == Field.SSH_AUTH_TYPE) {
            sshAuthType = sshAuthType == SshAuthType.PASSWORD ? SshAuthType.PRIVATE_KEY : SshAuthType.PASSWORD;
        }
    }

    public void handleChar(char c) {
        switch (focused) {
            case ALIAS -> alias += c;
            case HOST -> host += c;
            case PORT -> {
                if (Character.isDigit(c)) {
                    port += c;
                }
            }
            case USERNAME -> username += c;
            case PASSWORD -> password += c;
            case SSH_PORT -> {
                if (Character.isDigit(c)) {
                    sshPort += c;
                }
            }
            case SSH_KEY_PATH -> sshKeyPath += c;
            case SSH_PASSPHRASE -> sshPassphrase += c;
            case RMI_PORT -> {
                if (Character.isDigit(c)) {
                    rmiPort += c;
                }
            }
            case METHOD, AUTH, SSH_AUTH_TYPE -> {
                // not text-editable
            }
        }
    }

    public void handleBackspace() {
        switch (focused) {
            case ALIAS -> alias = trimLast(alias);
            case HOST -> host = trimLast(host);
            case PORT -> port = trimLast(port);
            case USERNAME -> username = trimLast(username);
            case PASSWORD -> password = trimLast(password);
            case SSH_PORT -> sshPort = trimLast(sshPort);
            case SSH_KEY_PATH -> sshKeyPath = trimLast(sshKeyPath);
            case SSH_PASSPHRASE -> sshPassphrase = trimLast(sshPassphrase);
            case RMI_PORT -> rmiPort = trimLast(rmiPort);
            case METHOD, AUTH, SSH_AUTH_TYPE -> {
                // not text-editable
            }
        }
    }

    private static String trimLast(String s) {
        return s.isEmpty() ? s : s.substring(0, s.length() - 1);
    }

    public interface OnSubmit {
        void submit(ConnectRequest request);
    }

    public void submit(OnSubmit callback) {
        if (alias.isBlank()) {
            validationError = "Alias is required";
            return;
        }
        if (host.isBlank()) {
            validationError = "Host is required";
            return;
        }
        int portValue = parsePort(port, "JMX port");
        if (portValue < 0) {
            return;
        }
        if (isSshTunnel()) {
            if (username.isBlank()) {
                validationError = "SSH username is required";
                return;
            }
            int sshPortValue = parsePort(sshPort, "SSH port");
            if (sshPortValue < 0) {
                return;
            }
            int rmiPortValue = parsePort(rmiPort, "RMI port");
            if (rmiPortValue < 0) {
                return;
            }
            if (sshAuthType == SshAuthType.PRIVATE_KEY && sshKeyPath.isBlank()) {
                validationError = "Private key path is required";
                return;
            }
            validationError = null;
            String pw = sshAuthType == SshAuthType.PASSWORD ? password : null;
            String keyPath = sshAuthType == SshAuthType.PRIVATE_KEY ? sshKeyPath : null;
            callback.submit(new ConnectRequest(alias, host, portValue, username, pw,
                    method, sshPortValue, keyPath, sshPassphrase, rmiPortValue));
            return;
        }
        validationError = null;
        callback.submit(new ConnectRequest(alias, host, portValue, useAuth ? username : null, useAuth ? password : null,
                method, 0, null, null, 0));
    }

    private int parsePort(String raw, String fieldLabel) {
        int value;
        try {
            value = Integer.parseInt(raw);
        } catch (NumberFormatException e) {
            validationError = fieldLabel + " must be a number";
            return -1;
        }
        if (value < 1 || value > 65535) {
            validationError = fieldLabel + " must be between 1 and 65535";
            return -1;
        }
        return value;
    }

    /**
     * @param connectError last connection-attempt failure (from the caller's
     *                     submit callback), or null. Shown only when there's
     *                     no local validation error, so the two never overlap.
     */
    public Element render(String connectError) {
        var rows = new ArrayList<Element>();
        rows.add(textRow("Alias", alias, focused == Field.ALIAS));
        rows.add(textRow("Host", host, focused == Field.HOST));
        rows.add(methodRow());
        if (isSshTunnel()) {
            rows.add(textRow("SSH Port", sshPort, focused == Field.SSH_PORT));
            rows.add(textRow("SSH User", username, focused == Field.USERNAME));
            rows.add(sshAuthTypeRow());
            if (sshAuthType == SshAuthType.PASSWORD) {
                rows.add(maskedRow("SSH Password", password, focused == Field.PASSWORD));
            } else {
                rows.add(textRow("Key Path", sshKeyPath, focused == Field.SSH_KEY_PATH));
                rows.add(maskedRow("Passphrase", sshPassphrase, focused == Field.SSH_PASSPHRASE));
            }
            rows.add(textRow("JMX Port", port, focused == Field.PORT));
            rows.add(textRow("RMI Port", rmiPort, focused == Field.RMI_PORT));
        } else {
            rows.add(textRow("Port", port, focused == Field.PORT));
            rows.add(authRow());
            if (useAuth) {
                rows.add(textRow("Username", username, focused == Field.USERNAME));
                rows.add(maskedRow("Password", password, focused == Field.PASSWORD));
            }
            rows.add(fieldRow("SSL/TLS", "[ ] not yet supported"));
        }
        String errorToShow = validationError != null ? validationError : connectError;
        if (errorToShow != null) {
            rows.add(row(text("  " + errorToShow).fg(Theme.STATUS_BAD)));
        }

        return dialog(rows.toArray(Element[]::new))
                .title(editMode ? "EDIT REMOTE CONNECTION" : "ADD REMOTE CONNECTION")
                .rounded()
                .borderColor(Theme.ACCENT)
                .width(46)
                .padding(1)
                .spacing(1)
                .id("add-remote-screen");
    }

    private static Element fieldRow(String label, String field) {
        return row(
                text(String.format("  %-10s", label)).fg(Theme.TEXT_MUTED),
                text(field).fg(Theme.TEXT_SECONDARY));
    }

    private static Element textRow(String label, String value, boolean focused) {
        String cursor = focused ? "_" : "";
        return row(
                text(String.format("  %-10s", label)).fg(focused ? Theme.TEXT_PRIMARY : Theme.TEXT_MUTED),
                text("[ " + value + cursor + " ]").fg(focused ? Theme.ACCENT_LIGHT : Theme.TEXT_SECONDARY));
    }

    private static Element maskedRow(String label, String value, boolean focused) {
        return textRow(label, "*".repeat(value.length()), focused);
    }

    private Element methodRow() {
        boolean focused = this.focused == Field.METHOD;
        String jmxMark = !isSshTunnel() ? "●" : "○";
        String sshMark = isSshTunnel() ? "●" : "○";
        return row(
                text(String.format("  %-10s", "Method")).fg(focused ? Theme.TEXT_PRIMARY : Theme.TEXT_MUTED),
                text(jmxMark + " Direct JMX   " + sshMark + " SSH Tunnel")
                        .fg(focused ? Theme.ACCENT_LIGHT : Theme.TEXT_SECONDARY));
    }

    private Element authRow() {
        boolean focused = this.focused == Field.AUTH;
        String noneMark = !useAuth ? "●" : "○";
        String authMark = useAuth ? "●" : "○";
        return row(
                text(String.format("  %-10s", "Auth")).fg(focused ? Theme.TEXT_PRIMARY : Theme.TEXT_MUTED),
                text(noneMark + " None   " + authMark + " Username & Password")
                        .fg(focused ? Theme.ACCENT_LIGHT : Theme.TEXT_SECONDARY));
    }

    private Element sshAuthTypeRow() {
        boolean focused = this.focused == Field.SSH_AUTH_TYPE;
        String pwMark = sshAuthType == SshAuthType.PASSWORD ? "●" : "○";
        String keyMark = sshAuthType == SshAuthType.PRIVATE_KEY ? "●" : "○";
        return row(
                text(String.format("  %-10s", "SSH Auth")).fg(focused ? Theme.TEXT_PRIMARY : Theme.TEXT_MUTED),
                text(pwMark + " Password   " + keyMark + " Private Key")
                        .fg(focused ? Theme.ACCENT_LIGHT : Theme.TEXT_SECONDARY));
    }
}
