package com.fari;

import com.fari.connection.ConnectionException;
import com.fari.connection.LocalAttachConnection;
import com.fari.connection.LocalProcessInfo;
import com.fari.connection.ProcessDiscovery;
import com.fari.metrics.JmxPollingMetricsSource;
import com.fari.metrics.MetricsSource;
import com.fari.ui.AddRemoteDialogScreen;
import com.fari.ui.ConnectionsScreen;
import com.fari.ui.OverviewScreen;
import dev.tamboui.toolkit.app.ToolkitApp;
import dev.tamboui.toolkit.element.Element;
import dev.tamboui.tui.event.KeyEvent;
import dev.tamboui.toolkit.event.EventResult;

import java.util.List;
import java.util.concurrent.CompletableFuture;

import static dev.tamboui.toolkit.Toolkit.column;

public class JvmMonitorTui extends ToolkitApp {

    private enum Screen {
        CONNECTIONS, ADD_REMOTE, OVERVIEW
    }

    private volatile Screen currentScreen = Screen.CONNECTIONS;
    private volatile String connectError;

    private final ConnectionsScreen connectionsScreen = new ConnectionsScreen();
    private final AddRemoteDialogScreen addRemoteScreen = new AddRemoteDialogScreen();
    private volatile OverviewScreen overviewScreen;
    private volatile MetricsSource metricsSource;

    @Override
    protected void onStart() {
        refreshProcesses();
    }

    private void refreshProcesses() {
        CompletableFuture.runAsync(() -> {
            List<LocalProcessInfo> processes = ProcessDiscovery.listLocalJvms();
            connectionsScreen.setProcesses(processes);
        });
    }

    @Override
    protected Element render() {
        Element content = switch (currentScreen) {
            case CONNECTIONS -> connectionsScreen.render(connectError);
            case ADD_REMOTE -> addRemoteScreen.render();
            case OVERVIEW -> overviewScreen != null ? overviewScreen.render() : connectionsScreen.render(connectError);
        };

        return column(content)
                .id("root")
                .focusable()
                .onKeyEvent(this::handleKeyEvent);
    }

    private EventResult handleKeyEvent(KeyEvent event) {
        if (event.isQuit()) {
            releaseMetrics();
            quit();
            return EventResult.HANDLED;
        }

        return switch (currentScreen) {
            case CONNECTIONS -> handleConnectionsKey(event);
            case ADD_REMOTE -> handleAddRemoteKey(event);
            case OVERVIEW -> handleOverviewKey(event);
        };
    }

    private EventResult handleConnectionsKey(KeyEvent event) {
        if (event.isUp()) {
            connectionsScreen.selectPrevious();
            return EventResult.HANDLED;
        }
        if (event.isDown()) {
            connectionsScreen.selectNext();
            return EventResult.HANDLED;
        }
        if (event.isConfirm()) {
            connectToSelected();
            return EventResult.HANDLED;
        }
        if (event.isChar('r')) {
            refreshProcesses();
            return EventResult.HANDLED;
        }
        if (event.isChar('n')) {
            currentScreen = Screen.ADD_REMOTE;
            return EventResult.HANDLED;
        }
        return EventResult.UNHANDLED;
    }

    private EventResult handleAddRemoteKey(KeyEvent event) {
        if (event.isCancel()) {
            currentScreen = Screen.CONNECTIONS;
            return EventResult.HANDLED;
        }
        return EventResult.UNHANDLED;
    }

    private EventResult handleOverviewKey(KeyEvent event) {
        if (event.isCancel()) {
            disconnect();
            return EventResult.HANDLED;
        }
        return EventResult.UNHANDLED;
    }

    private void connectToSelected() {
        LocalProcessInfo process = connectionsScreen.selected();
        if (process == null) {
            return;
        }
        CompletableFuture.runAsync(() -> {
            try {
                var connection = new LocalAttachConnection(process.pid(), process.displayName());
                var source = new JmxPollingMetricsSource();
                source.start(connection);
                metricsSource = source;
                overviewScreen = new OverviewScreen(source);
                connectError = null;
                currentScreen = Screen.OVERVIEW;
            } catch (ConnectionException e) {
                connectError = e.getMessage();
            }
        });
    }

    private void disconnect() {
        releaseMetrics();
        currentScreen = Screen.CONNECTIONS;
        refreshProcesses();
    }

    private void releaseMetrics() {
        MetricsSource source = metricsSource;
        if (source != null) {
            source.close();
            metricsSource = null;
        }
        overviewScreen = null;
    }

    public static void main(String[] args) throws Exception {
        var app = new JvmMonitorTui();
        // Safety net for Ctrl+C/SIGTERM/any exit path that bypasses the key
        // handler — the 'q' path already closes metricsSource in handleKeyEvent.
        Runtime.getRuntime().addShutdownHook(new Thread(app::releaseMetrics));
        app.run();
    }
}
