package com.fari.ui;

import dev.tamboui.toolkit.element.Element;

import static dev.tamboui.toolkit.Toolkit.*;

/**
 * Static shell only, per the mock's field layout — no TextInput wiring, no
 * validation, no save logic. Remote connection types are not implemented
 * this pass (see docs/spec/open-questions.md).
 */
public final class AddRemoteDialogScreen {

    public Element render() {
        return dialog(
                fieldRow("Alias", "[ ]"),
                fieldRow("Host", "[ ]"),
                fieldRow("Port", "[ ]"),
                fieldRow("Protocol", "( ) JMX (RMI)   ( ) JMX (JMXMP)"),
                fieldRow("Auth", "( ) None   ( ) Username & Password"),
                fieldRow("Username", "[ ]"),
                fieldRow("Password", "[ ]"),
                fieldRow("SSL/TLS", "[ ] use SSL/TLS for this connection")
        ).title("ADD REMOTE CONNECTION").rounded().borderColor(Theme.ACCENT).id("add-remote-screen");
    }

    private static Element fieldRow(String label, String field) {
        return row(
                text(String.format("  %-10s", label)).fg(Theme.TEXT_MUTED),
                text(field).fg(Theme.TEXT_SECONDARY)
        );
    }
}
