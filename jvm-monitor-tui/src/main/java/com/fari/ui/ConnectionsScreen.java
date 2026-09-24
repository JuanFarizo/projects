package com.fari.ui;

import com.fari.connection.LocalProcessInfo;
import com.fari.connection.SavedConnection;
import dev.tamboui.toolkit.element.Element;
import dev.tamboui.widgets.table.Row;
import dev.tamboui.widgets.table.TableState;

import java.util.ArrayList;
import java.util.List;

import static dev.tamboui.toolkit.Toolkit.*;

/** Local JVM process picker + saved remote connections. */
public final class ConnectionsScreen {

    public enum Panel { PROCESSES, REMOTES }

    public enum PromptField { USERNAME, PASSWORD }

    private final TableState tableState = new TableState();
    private final TableState remoteTableState = new TableState();
    private List<LocalProcessInfo> processes = List.of();
    private List<SavedConnection> savedConnections = List.of();
    private Panel focusedPanel = Panel.PROCESSES;

    // Inline reconnect re-prompt (decision: only username/password, not the
    // full Add Remote dialog — shown when confirming a saved profile that
    // used auth).
    private boolean prompting = false;
    private SavedConnection promptTarget;
    private String promptUsername = "";
    private String promptPassword = "";
    private PromptField promptFocused = PromptField.USERNAME;

    public void setProcesses(List<LocalProcessInfo> processes) {
        this.processes = processes;
        if (tableState.selected() == null && !processes.isEmpty()) {
            tableState.selectFirst();
        }
    }

    public void setSavedConnections(List<SavedConnection> savedConnections) {
        this.savedConnections = savedConnections;
        if (remoteTableState.selected() == null && !savedConnections.isEmpty()) {
            remoteTableState.selectFirst();
        }
    }

    public Panel focusedPanel() {
        return focusedPanel;
    }

    public void togglePanel() {
        focusedPanel = focusedPanel == Panel.PROCESSES ? Panel.REMOTES : Panel.PROCESSES;
    }

    public void selectNext() {
        if (focusedPanel == Panel.PROCESSES) {
            if (!processes.isEmpty()) {
                tableState.selectNext(processes.size());
            }
        } else if (!savedConnections.isEmpty()) {
            remoteTableState.selectNext(savedConnections.size());
        }
    }

    public void selectPrevious() {
        if (focusedPanel == Panel.PROCESSES) {
            if (!processes.isEmpty()) {
                tableState.selectPrevious();
            }
        } else if (!savedConnections.isEmpty()) {
            remoteTableState.selectPrevious();
        }
    }

    public LocalProcessInfo selected() {
        Integer index = tableState.selected();
        if (index == null || index < 0 || index >= processes.size()) {
            return null;
        }
        return processes.get(index);
    }

    public SavedConnection selectedSaved() {
        Integer index = remoteTableState.selected();
        if (index == null || index < 0 || index >= savedConnections.size()) {
            return null;
        }
        return savedConnections.get(index);
    }

    // ==================== Reconnect prompt ====================

    public boolean isPrompting() {
        return prompting;
    }

    public void startReconnectPrompt(SavedConnection target) {
        prompting = true;
        promptTarget = target;
        promptUsername = target.username();
        promptPassword = "";
        promptFocused = PromptField.USERNAME;
    }

    public void cancelReconnectPrompt() {
        prompting = false;
        promptTarget = null;
    }

    public SavedConnection promptTarget() {
        return promptTarget;
    }

    public String promptUsername() {
        return promptUsername;
    }

    public String promptPassword() {
        return promptPassword;
    }

    public void promptToggleFocus() {
        promptFocused = promptFocused == PromptField.USERNAME ? PromptField.PASSWORD : PromptField.USERNAME;
    }

    public boolean promptIsOnLastField() {
        return promptFocused == PromptField.PASSWORD;
    }

    public void promptHandleChar(char c) {
        if (promptFocused == PromptField.USERNAME) {
            promptUsername += c;
        } else {
            promptPassword += c;
        }
    }

    public void promptHandleBackspace() {
        if (promptFocused == PromptField.USERNAME) {
            promptUsername = trimLast(promptUsername);
        } else {
            promptPassword = trimLast(promptPassword);
        }
    }

    private static String trimLast(String s) {
        return s.isEmpty() ? s : s.substring(0, s.length() - 1);
    }

    // ==================== Rendering ====================

    public Element render(String connectError) {
        var rows = processes.stream()
                .map(p -> Row.from(p.pid(), p.displayName()))
                .toList();

        var processesTable = table()
                .header(Row.from("PID", "Main Class"))
                .rows(rows)
                .state(tableState)
                .widths(percent(20), fill())
                .highlightColor(Theme.ACCENT);

        var localPanel = panel("LOCAL PROCESSES", processesTable)
                .rounded()
                .borderColor(focusedPanel == Panel.PROCESSES ? Theme.ACCENT : Theme.BORDER);

        Element remoteContent = prompting ? renderReconnectPrompt() : renderSavedConnectionsTable();
        var remotePanel = panel("SAVED REMOTE CONNECTIONS", remoteContent)
                .rounded()
                .borderColor(focusedPanel == Panel.REMOTES ? Theme.ACCENT : Theme.BORDER);

        List<Element> elements = new ArrayList<>();
        elements.add(localPanel);
        elements.add(remotePanel);
        if (connectError != null) {
            elements.add(text("  " + connectError).fg(Theme.STATUS_BAD));
        }

        return column(elements.toArray(Element[]::new)).id("connections-screen");
    }

    private Element renderSavedConnectionsTable() {
        if (savedConnections.isEmpty()) {
            return text("No saved connections yet — press n to add one.").fg(Theme.TEXT_MUTED);
        }
        var rows = savedConnections.stream()
                .map(c -> Row.from(c.alias(), c.host() + ":" + c.port()))
                .toList();
        return table()
                .header(Row.from("Alias", "Host:Port"))
                .rows(rows)
                .state(remoteTableState)
                .widths(percent(30), fill())
                .highlightColor(Theme.ACCENT);
    }

    private Element renderReconnectPrompt() {
        boolean userFocused = promptFocused == PromptField.USERNAME;
        boolean passFocused = promptFocused == PromptField.PASSWORD;
        return column(
                text("  Reconnect to " + (promptTarget != null ? promptTarget.alias() : "")).fg(Theme.TEXT_SECONDARY),
                row(
                        text("  Username  ").fg(userFocused ? Theme.TEXT_PRIMARY : Theme.TEXT_MUTED),
                        text("[ " + promptUsername + (userFocused ? "_" : "") + " ]")
                                .fg(userFocused ? Theme.ACCENT_LIGHT : Theme.TEXT_SECONDARY)
                ),
                row(
                        text("  Password  ").fg(passFocused ? Theme.TEXT_PRIMARY : Theme.TEXT_MUTED),
                        text("[ " + "*".repeat(promptPassword.length()) + (passFocused ? "_" : "") + " ]")
                                .fg(passFocused ? Theme.ACCENT_LIGHT : Theme.TEXT_SECONDARY)
                )
        );
    }
}
