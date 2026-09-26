package com.fari.ui;

import com.fari.connection.DockerContainerInfo;
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

    public enum Panel { PROCESSES, DOCKER, REMOTES }

    public enum PromptField { USERNAME, PASSWORD }

    private final TableState tableState = new TableState();
    private final TableState dockerTableState = new TableState();
    private final TableState remoteTableState = new TableState();
    private List<LocalProcessInfo> processes = List.of();
    private List<DockerContainerInfo> dockerContainers = List.of();
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

    // Inline delete confirmation — same shape as the reconnect prompt above.
    private boolean confirmingDelete = false;
    private SavedConnection deleteTarget;

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

    public void setDockerContainers(List<DockerContainerInfo> dockerContainers) {
        this.dockerContainers = dockerContainers;
        if (dockerTableState.selected() == null && !dockerContainers.isEmpty()) {
            dockerTableState.selectFirst();
        }
    }

    public Panel focusedPanel() {
        return focusedPanel;
    }

    private static final Panel[] PANELS = Panel.values();

    public void focusNext() {
        focusedPanel = PANELS[(focusedPanel.ordinal() + 1) % PANELS.length];
    }

    public void focusPrevious() {
        focusedPanel = PANELS[(focusedPanel.ordinal() - 1 + PANELS.length) % PANELS.length];
    }

    public void selectNext() {
        switch (focusedPanel) {
            case PROCESSES -> {
                if (!processes.isEmpty()) {
                    tableState.selectNext(processes.size());
                }
            }
            case DOCKER -> {
                if (!dockerContainers.isEmpty()) {
                    dockerTableState.selectNext(dockerContainers.size());
                }
            }
            case REMOTES -> {
                if (!savedConnections.isEmpty()) {
                    remoteTableState.selectNext(savedConnections.size());
                }
            }
        }
    }

    public void selectPrevious() {
        switch (focusedPanel) {
            case PROCESSES -> {
                if (!processes.isEmpty()) {
                    tableState.selectPrevious();
                }
            }
            case DOCKER -> {
                if (!dockerContainers.isEmpty()) {
                    dockerTableState.selectPrevious();
                }
            }
            case REMOTES -> {
                if (!savedConnections.isEmpty()) {
                    remoteTableState.selectPrevious();
                }
            }
        }
    }

    public LocalProcessInfo selected() {
        Integer index = tableState.selected();
        if (index == null || index < 0 || index >= processes.size()) {
            return null;
        }
        return processes.get(index);
    }

    public DockerContainerInfo selectedDocker() {
        Integer index = dockerTableState.selected();
        if (index == null || index < 0 || index >= dockerContainers.size()) {
            return null;
        }
        return dockerContainers.get(index);
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

    // ==================== Delete confirmation ====================

    public boolean isConfirmingDelete() {
        return confirmingDelete;
    }

    public void startDeleteConfirm(SavedConnection target) {
        confirmingDelete = true;
        deleteTarget = target;
    }

    public void cancelDeleteConfirm() {
        confirmingDelete = false;
        deleteTarget = null;
    }

    public SavedConnection deleteTarget() {
        return deleteTarget;
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

        var dockerPanel = panel("DOCKER CONTAINERS", renderDockerTable())
                .rounded()
                .borderColor(focusedPanel == Panel.DOCKER ? Theme.ACCENT : Theme.BORDER);

        Element remoteContent = prompting ? renderReconnectPrompt()
                : confirmingDelete ? renderDeleteConfirm()
                : renderSavedConnectionsTable();
        var remotePanel = panel("SAVED REMOTE CONNECTIONS", remoteContent)
                .rounded()
                .borderColor(focusedPanel == Panel.REMOTES ? Theme.ACCENT : Theme.BORDER);

        List<Element> elements = new ArrayList<>();
        elements.add(localPanel);
        elements.add(dockerPanel);
        elements.add(remotePanel);
        if (connectError != null) {
            elements.add(text("  " + connectError).fg(Theme.STATUS_BAD));
        }

        return column(elements.toArray(Element[]::new)).id("connections-screen");
    }

    private Element renderDeleteConfirm() {
        String alias = deleteTarget != null ? deleteTarget.alias() : "";
        return column(
                text("  Delete " + alias + "?").fg(Theme.STATUS_BAD),
                text("  y: confirm   n / esc: cancel").fg(Theme.TEXT_MUTED)
        );
    }

    private Element renderDockerTable() {
        if (dockerContainers.isEmpty()) {
            return text("No containers labeled jvm-monitor.enabled=true found — press r to refresh.").fg(Theme.TEXT_MUTED);
        }
        var rows = dockerContainers.stream()
                .map(c -> Row.from(c.name(), c.image(), formatPorts(c)))
                .toList();
        return table()
                .header(Row.from("Name", "Image", "Ports"))
                .rows(rows)
                .state(dockerTableState)
                .widths(percent(25), percent(35), fill())
                .highlightColor(Theme.ACCENT);
    }

    private static String formatPorts(DockerContainerInfo c) {
        return c.publishedTcpPorts().stream()
                .map(String::valueOf)
                .reduce((a, b) -> a + ", " + b)
                .orElse("");
    }

    private Element renderSavedConnectionsTable() {
        if (savedConnections.isEmpty()) {
            return text("No saved connections yet — press n to add one.").fg(Theme.TEXT_MUTED);
        }
        var rows = savedConnections.stream()
                .map(c -> Row.from(c.alias(), c.host() + ":" + c.port(), c.isSshTunnel() ? "SSH" : "JMX"))
                .toList();
        return table()
                .header(Row.from("Alias", "Host:Port", "Via"))
                .rows(rows)
                .state(remoteTableState)
                .widths(percent(30), fill(), percent(15))
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
