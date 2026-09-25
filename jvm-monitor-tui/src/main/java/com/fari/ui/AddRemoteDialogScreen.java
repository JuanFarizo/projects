package com.fari.ui;

import com.fari.connection.SavedConnection;
import dev.tamboui.toolkit.element.Element;

import static dev.tamboui.toolkit.Toolkit.*;

import java.util.ArrayList;

/**
 * Direct Remote JMX connect form (method 2 — RMI only, no JMXMP/SSL this
 * pass). Hand-rolled keyboard-driven form matching this codebase's existing
 * manual-dispatch convention (ConnectionsScreen's up/down+TableState), not
 * TamboUI's FormElement/FocusManager subsystem.
 * <p>
 * Doubles as the edit form for a saved connection ({@link #startEdit}) —
 * same fields, password always starts blank since it's never persisted.
 */
public final class AddRemoteDialogScreen {

    public enum Field { ALIAS, HOST, PORT, AUTH, USERNAME, PASSWORD }

    private Field focused = Field.ALIAS;
    private String alias = "";
    private String host = "";
    private String port = "";
    private boolean useAuth = false;
    private String username = "";
    private String password = "";
    private String validationError;
    private boolean editMode = false;
    private String editId;

    public void reset() {
        focused = Field.ALIAS;
        alias = "";
        host = "";
        port = "";
        useAuth = false;
        username = "";
        password = "";
        validationError = null;
        editMode = false;
        editId = null;
    }

    /** Prefills the form from an existing saved connection; password stays blank (never persisted). */
    public void startEdit(SavedConnection existing) {
        focused = Field.ALIAS;
        alias = existing.alias();
        host = existing.host();
        port = String.valueOf(existing.port());
        useAuth = existing.hasAuth();
        username = existing.username();
        password = "";
        validationError = null;
        editMode = true;
        editId = existing.id();
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

    private static Field[] activeOrder(boolean useAuth) {
        return useAuth
                ? new Field[]{Field.ALIAS, Field.HOST, Field.PORT, Field.AUTH, Field.USERNAME, Field.PASSWORD}
                : new Field[]{Field.ALIAS, Field.HOST, Field.PORT, Field.AUTH};
    }

    /** True when Enter on the current field should submit rather than advance. */
    public boolean isOnLastField() {
        Field[] order = activeOrder(useAuth);
        return order[order.length - 1] == focused;
    }

    public void focusNext() {
        Field[] order = activeOrder(useAuth);
        int idx = indexOf(order, focused);
        focused = order[(idx + 1) % order.length];
    }

    public void focusPrevious() {
        Field[] order = activeOrder(useAuth);
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
            case AUTH -> {
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
            case AUTH -> {
                // not text-editable
            }
        }
    }

    private static String trimLast(String s) {
        return s.isEmpty() ? s : s.substring(0, s.length() - 1);
    }

    /** Validates the form; returns null (and clears alias/host/port + resets state) on success, or the resolved values via the callback. */
    public interface OnSubmit {
        void submit(String alias, String host, int port, String username, String password);
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
        int portValue;
        try {
            portValue = Integer.parseInt(port);
        } catch (NumberFormatException e) {
            validationError = "Port must be a number";
            return;
        }
        if (portValue < 1 || portValue > 65535) {
            validationError = "Port must be between 1 and 65535";
            return;
        }
        validationError = null;
        callback.submit(alias, host, portValue, useAuth ? username : null, useAuth ? password : null);
    }

    /**
     * @param connectError last connection-attempt failure (from the caller's
     *                      submit callback), or null. Shown only when there's
     *                      no local validation error, so the two never overlap.
     */
    public Element render(String connectError) {
        var rows = new ArrayList<Element>();
        rows.add(textRow("Alias", alias, focused == Field.ALIAS));
        rows.add(textRow("Host", host, focused == Field.HOST));
        rows.add(textRow("Port", port, focused == Field.PORT));
        rows.add(fieldRow("Protocol", "JMX (RMI)"));
        rows.add(authRow());
        if (useAuth) {
            rows.add(textRow("Username", username, focused == Field.USERNAME));
            rows.add(maskedRow("Password", password, focused == Field.PASSWORD));
        }
        rows.add(fieldRow("SSL/TLS", "[ ] not yet supported"));
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
                text(field).fg(Theme.TEXT_SECONDARY)
        );
    }

    private static Element textRow(String label, String value, boolean focused) {
        String cursor = focused ? "_" : "";
        return row(
                text(String.format("  %-10s", label)).fg(focused ? Theme.TEXT_PRIMARY : Theme.TEXT_MUTED),
                text("[ " + value + cursor + " ]").fg(focused ? Theme.ACCENT_LIGHT : Theme.TEXT_SECONDARY)
        );
    }

    private static Element maskedRow(String label, String value, boolean focused) {
        return textRow(label, "*".repeat(value.length()), focused);
    }

    private Element authRow() {
        boolean focused = this.focused == Field.AUTH;
        String noneMark = !useAuth ? "●" : "○";
        String authMark = useAuth ? "●" : "○";
        return row(
                text(String.format("  %-10s", "Auth")).fg(focused ? Theme.TEXT_PRIMARY : Theme.TEXT_MUTED),
                text(noneMark + " None   " + authMark + " Username & Password")
                        .fg(focused ? Theme.ACCENT_LIGHT : Theme.TEXT_SECONDARY)
        );
    }
}
