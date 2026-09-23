package com.fari.ui;

import com.fari.connection.LocalProcessInfo;
import dev.tamboui.toolkit.element.Element;
import dev.tamboui.widgets.table.Row;
import dev.tamboui.widgets.table.TableState;

import java.util.ArrayList;
import java.util.List;

import static dev.tamboui.toolkit.Toolkit.*;

/** Local JVM process picker. No remote-connection data — see AddRemoteDialogScreen. */
public final class ConnectionsScreen {

    private final TableState tableState = new TableState();
    private List<LocalProcessInfo> processes = List.of();

    public void setProcesses(List<LocalProcessInfo> processes) {
        this.processes = processes;
        if (tableState.selected() == null && !processes.isEmpty()) {
            tableState.selectFirst();
        }
    }

    public void selectNext() {
        if (!processes.isEmpty()) {
            tableState.selectNext(processes.size());
        }
    }

    public void selectPrevious() {
        if (!processes.isEmpty()) {
            tableState.selectPrevious();
        }
    }

    public LocalProcessInfo selected() {
        Integer index = tableState.selected();
        if (index == null || index < 0 || index >= processes.size()) {
            return null;
        }
        return processes.get(index);
    }

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

        var localPanel = panel("LOCAL PROCESSES", processesTable).rounded().borderColor(Theme.BORDER);

        var remotePanel = panel("SAVED REMOTE CONNECTIONS",
                text("No saved connections yet — remote connections are not implemented in this build.")
                        .fg(Theme.TEXT_MUTED)
        ).rounded().borderColor(Theme.BORDER);

        List<Element> elements = new ArrayList<>();
        elements.add(localPanel);
        elements.add(remotePanel);
        if (connectError != null) {
            elements.add(text("  " + connectError).fg(Theme.STATUS_BAD));
        }

        return column(elements.toArray(Element[]::new)).id("connections-screen");
    }
}
