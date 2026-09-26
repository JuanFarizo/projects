package com.fari;

import com.fari.connection.ConnectionException;
import com.fari.connection.DockerContainerInfo;
import com.fari.connection.DockerDiscovery;
import com.fari.connection.LocalAttachConnection;
import com.fari.connection.LocalProcessInfo;
import com.fari.connection.ProcessDiscovery;
import com.fari.connection.ConnectionHandle;
import com.fari.connection.RemoteJmxConnection;
import com.fari.connection.SavedConnection;
import com.fari.connection.SavedConnectionsStore;
import com.fari.connection.SshTunnelConnection;
import com.fari.metrics.DeadlockedThread;
import com.fari.metrics.JmxPollingMetricsSource;
import com.fari.metrics.MetricsSource;
import com.fari.ui.AddRemoteDialogScreen;
import com.fari.ui.ClassesScreen;
import com.fari.ui.ConnectionsScreen;
import com.fari.ui.GcLogScreen;
import com.fari.ui.MemoryScreen;
import com.fari.ui.OverviewScreen;
import com.fari.ui.Theme;
import com.fari.ui.ThreadsScreen;
import dev.tamboui.toolkit.app.ToolkitApp;
import dev.tamboui.toolkit.element.Element;
import dev.tamboui.tui.event.KeyEvent;
import dev.tamboui.toolkit.event.EventResult;

import java.util.Arrays;
import java.util.List;
import java.util.concurrent.CompletableFuture;

import static dev.tamboui.toolkit.Toolkit.column;
import static dev.tamboui.toolkit.Toolkit.row;
import static dev.tamboui.toolkit.Toolkit.spacer;
import static dev.tamboui.toolkit.Toolkit.text;

public class JvmMonitorTui extends ToolkitApp {

    private enum Screen {
        CONNECTIONS, ADD_REMOTE, OVERVIEW, MEMORY, THREADS, GC_LOG, CLASSES
    }

    private volatile Screen currentScreen = Screen.CONNECTIONS;
    private volatile String connectError;
    // Sorted IDs of the deadlock last dismissed with 'x'; banner stays hidden
    // until this set changes (new incident) or clears (resolved).
    private volatile long[] dismissedDeadlockIds = null;

    private final ConnectionsScreen connectionsScreen = new ConnectionsScreen();
    private final AddRemoteDialogScreen addRemoteScreen = new AddRemoteDialogScreen();
    private volatile OverviewScreen overviewScreen;
    private volatile MemoryScreen memoryScreen;
    private volatile ThreadsScreen threadsScreen;
    private volatile GcLogScreen gcLogScreen;
    private volatile ClassesScreen classesScreen;
    private volatile MetricsSource metricsSource;

    @Override
    protected void onStart() {
        refreshProcesses();
        refreshDockerContainers();
        refreshSavedConnections();
    }

    private void refreshProcesses() {
        CompletableFuture.runAsync(() -> {
            List<LocalProcessInfo> processes = ProcessDiscovery.listLocalJvms();
            connectionsScreen.setProcesses(processes);
        });
    }

    private void refreshDockerContainers() {
        CompletableFuture.runAsync(() -> {
            try {
                List<DockerContainerInfo> containers = DockerDiscovery.listContainers();
                connectionsScreen.setDockerContainers(containers);
                connectError = null;
            } catch (ConnectionException e) {
                connectError = e.getMessage();
            }
        });
    }

    private void refreshSavedConnections() {
        CompletableFuture.runAsync(() -> {
            List<SavedConnection> saved = SavedConnectionsStore.load(SavedConnectionsStore.defaultPath());
            connectionsScreen.setSavedConnections(saved);
        });
    }

    @Override
    protected Element render() {
        Element content = switch (currentScreen) {
            case CONNECTIONS -> connectionsScreen.render(connectError);
            case ADD_REMOTE -> addRemoteScreen.render(connectError);
            case OVERVIEW -> overviewScreen != null ? overviewScreen.render() : connectionsScreen.render(connectError);
            case MEMORY -> memoryScreen != null ? memoryScreen.render() : connectionsScreen.render(connectError);
            case THREADS -> threadsScreen != null ? threadsScreen.render() : connectionsScreen.render(connectError);
            case GC_LOG -> gcLogScreen != null ? gcLogScreen.render() : connectionsScreen.render(connectError);
            case CLASSES -> classesScreen != null ? classesScreen.render() : connectionsScreen.render(connectError);
        };

        Element banner = deadlockBanner();
        var children = new java.util.ArrayList<Element>();
        children.add(appHeader());
        if (banner != null) {
            children.add(banner);
        }
        children.add(content);
        // Footer is metrics-screen navigation — meaningless before a connection.
        if (metricsSource != null) {
            children.add(globalFooter());
        } else if (currentScreen == Screen.CONNECTIONS) {
            children.add(connectionsFooter());
        }

        return column(children.toArray(Element[]::new))
                .id("root")
                .focusable()
                .onKeyEvent(this::handleKeyEvent);
    }

    // One-line app identity strip shown above every screen, same composition
    // point as the footer/banner below.
    private Element appHeader() {
        MetricsSource source = metricsSource;
        String rightSide = source != null
                ? "attached · " + source.snapshot().vmInfo().label()
                : "not attached";
        return column(
                row(
                        text(" " + Theme.APP_NAME).fg(Theme.ACCENT).bold(),
                        text("  " + Theme.APP_VERSION).fg(Theme.TEXT_MUTED),
                        spacer(),
                        text(rightSide + " ").fg(Theme.TEXT_MUTED)
                ),
                text("─".repeat(300)).fg(Theme.TEXT_MUTED)
        ).length(2);
    }

    // Full command reference, identical on every screen (not all keys apply
    // to every screen — this is a persistent legend, not a context-sensitive
    // hint line). Replaces each screen's own ad hoc footer.
    private Element globalFooter() {
        return row(
                key("[1]", currentScreen == Screen.CONNECTIONS), label("connections", currentScreen == Screen.CONNECTIONS),
                key("[2]", currentScreen == Screen.OVERVIEW), label("overview", currentScreen == Screen.OVERVIEW),
                key("[c]", currentScreen == Screen.CLASSES), label("classes", currentScreen == Screen.CLASSES),
                key("[m]", currentScreen == Screen.MEMORY), label("memory", currentScreen == Screen.MEMORY),
                key("[t]", currentScreen == Screen.THREADS), label("threads", currentScreen == Screen.THREADS),
                key("[g]", currentScreen == Screen.GC_LOG), label("gc log", currentScreen == Screen.GC_LOG),
                text(" |  ").fg(Theme.TEXT_MUTED),
                key("[esc]", false), label("back", false),
                key("[q]", false), label("quit", false),
                spacer()
        ).length(1);
    }

    // Same legend style as globalFooter, scoped to what the Connections
    // screen's two panels actually support
    private Element connectionsFooter() {
        return row(
                key("[enter]", false), label("connect", false),
                key("[n]", false), label("add", false),
                key("[e]", false), label("edit", false),
                key("[d]", false), label("delete", false),
                key("[r]", false), label("refresh", false),
                text(" |  ").fg(Theme.TEXT_MUTED),
                key("[q]", false), label("quit", false),
                spacer()
        ).length(1);
    }

    // Highlights the entry matching currentScreen
    private static Element key(String k, boolean active) {
        return active
                ? text(k).fg(Theme.ACCENT).bold()
                : text(k).fg(Theme.TEXT_PRIMARY);
    }

    private static Element label(String l, boolean active) {
        return text(":" + l + "  ").fg(active ? Theme.ACCENT : Theme.TEXT_MUTED);
    }

    // Hidden on THREADS (full deadlock panel already shown there); naturally
    // absent pre-connect too since ThreadSnapshot.empty() has no deadlocks.
    private Element deadlockBanner() {
        if (currentScreen == Screen.THREADS) {
            return null;
        }
        List<DeadlockedThread> deadlockedThreads = currentDeadlockedThreads();
        if (deadlockedThreads.isEmpty()) {
            // Resolved — clear dismissal so a future incident isn't muted.
            dismissedDeadlockIds = null;
            return null;
        }
        if (Arrays.equals(deadlockedThreadIds(deadlockedThreads), dismissedDeadlockIds)) {
            return null;
        }
        return row(
                text(" DEADLOCK: " + deadlockedThreads.size() + " threads").fg(Theme.STATUS_BAD).bold(),
                spacer(),
                text("press t for details, x to dismiss ").fg(Theme.STATUS_BAD)
        ).length(1);
    }

    private List<DeadlockedThread> currentDeadlockedThreads() {
        MetricsSource source = metricsSource;
        if (source == null) {
            return List.of();
        }
        return source.snapshot().threads().deadlockedThreads();
    }

    private static long[] deadlockedThreadIds(List<DeadlockedThread> threads) {
        return threads.stream().mapToLong(DeadlockedThread::threadId).sorted().toArray();
    }

    private void dismissDeadlockBanner() {
        List<DeadlockedThread> deadlockedThreads = currentDeadlockedThreads();
        if (!deadlockedThreads.isEmpty()) {
            dismissedDeadlockIds = deadlockedThreadIds(deadlockedThreads);
        }
    }

    private EventResult handleKeyEvent(KeyEvent event) {
        if (event.isQuit()) {
            releaseMetrics();
            quit();
            return EventResult.HANDLED;
        }
        // Global on every screen — jump straight to Connections/Overview
        // instead of backing out one level at a time. Suppressed while a
        // keyboard text field has focus (Add Remote form, saved-connection
        // reconnect prompt) so typed letters like 'm'/'t'/'g'/'c'/'x'/'1'/'2'
        // reach the field instead of being swallowed as navigation shortcuts.
        boolean textEntryActive = currentScreen == Screen.ADD_REMOTE
                || (currentScreen == Screen.CONNECTIONS && connectionsScreen.isPrompting());
        if (!textEntryActive) {
            if (event.isChar('1')) {
                if (metricsSource != null) {
                    disconnect();
                } else {
                    currentScreen = Screen.CONNECTIONS;
                }
                return EventResult.HANDLED;
            }
            if (event.isChar('2')) {
                if (metricsSource != null) {
                    currentScreen = Screen.OVERVIEW;
                }
                return EventResult.HANDLED;
            }
            if (event.isChar('x')) {
                dismissDeadlockBanner();
                return EventResult.HANDLED;
            }
            if (event.isChar('m')) {
                if (metricsSource != null) {
                    currentScreen = Screen.MEMORY;
                }
                return EventResult.HANDLED;
            }
            if (event.isChar('t')) {
                if (metricsSource != null) {
                    currentScreen = Screen.THREADS;
                }
                return EventResult.HANDLED;
            }
            if (event.isChar('g')) {
                if (metricsSource != null) {
                    currentScreen = Screen.GC_LOG;
                }
                return EventResult.HANDLED;
            }
            if (event.isChar('c')) {
                if (metricsSource != null) {
                    currentScreen = Screen.CLASSES;
                }
                return EventResult.HANDLED;
            }
        }

        return switch (currentScreen) {
            case CONNECTIONS -> handleConnectionsKey(event);
            case ADD_REMOTE -> handleAddRemoteKey(event);
            case OVERVIEW -> handleOverviewKey(event);
            case MEMORY, THREADS, GC_LOG, CLASSES -> handleDetailScreenKey(event);
        };
    }

    private EventResult handleConnectionsKey(KeyEvent event) {
        if (connectionsScreen.isPrompting()) {
            return handleReconnectPromptKey(event);
        }
        if (connectionsScreen.isConfirmingDelete()) {
            return handleDeleteConfirmKey(event);
        }
        if (event.isUp()) {
            connectionsScreen.selectPrevious();
            return EventResult.HANDLED;
        }
        if (event.isDown()) {
            connectionsScreen.selectNext();
            return EventResult.HANDLED;
        }
        if (event.isLeft()) {
            connectionsScreen.focusPrevious();
            return EventResult.HANDLED;
        }
        if (event.isRight()) {
            connectionsScreen.focusNext();
            return EventResult.HANDLED;
        }
        if (event.isConfirm()) {
            switch (connectionsScreen.focusedPanel()) {
                case PROCESSES -> connectToSelected();
                case DOCKER -> connectToSelectedDocker();
                case REMOTES -> confirmSelectedSaved();
            }
            return EventResult.HANDLED;
        }
        if (event.isChar('r')) {
            switch (connectionsScreen.focusedPanel()) {
                case PROCESSES -> refreshProcesses();
                case DOCKER -> refreshDockerContainers();
                case REMOTES -> { /* saved connections load from disk, nothing to refresh */ }
            }
            return EventResult.HANDLED;
        }
        if (event.isChar('n')) {
            addRemoteScreen.reset();
            connectError = null;
            currentScreen = Screen.ADD_REMOTE;
            return EventResult.HANDLED;
        }
        if (event.isChar('e') && connectionsScreen.focusedPanel() == ConnectionsScreen.Panel.REMOTES) {
            var saved = connectionsScreen.selectedSaved();
            if (saved != null) {
                addRemoteScreen.startEdit(saved);
                connectError = null;
                currentScreen = Screen.ADD_REMOTE;
            }
            return EventResult.HANDLED;
        }
        if (event.isChar('d') && connectionsScreen.focusedPanel() == ConnectionsScreen.Panel.REMOTES) {
            var saved = connectionsScreen.selectedSaved();
            if (saved != null) {
                connectionsScreen.startDeleteConfirm(saved);
            }
            return EventResult.HANDLED;
        }
        return EventResult.UNHANDLED;
    }

    private EventResult handleDeleteConfirmKey(KeyEvent event) {
        if (event.isCancel() || event.isChar('n')) {
            connectionsScreen.cancelDeleteConfirm();
            return EventResult.HANDLED;
        }
        if (event.isConfirm() || event.isChar('y')) {
            var target = connectionsScreen.deleteTarget();
            connectionsScreen.cancelDeleteConfirm();
            deleteSavedConnection(target);
            return EventResult.HANDLED;
        }
        return EventResult.UNHANDLED;
    }

    private void deleteSavedConnection(SavedConnection target) {
        CompletableFuture.runAsync(() -> {
            var path = SavedConnectionsStore.defaultPath();
            var updated = SavedConnectionsStore.delete(SavedConnectionsStore.load(path), target.id());
            SavedConnectionsStore.save(path, updated);
            connectionsScreen.setSavedConnections(updated);
        });
    }

    // SSH tunnel reconnect always goes through the full Add Remote form — the
    // small inline username/password prompt below only fits the direct-JMX
    // shape (it can't collect an SSH port, key path, or key passphrase).
    private void confirmSelectedSaved() {
        var saved = connectionsScreen.selectedSaved();
        if (saved == null) {
            return;
        }
        if (saved.isSshTunnel()) {
            addRemoteScreen.startReconnect(saved);
            connectError = null;
            currentScreen = Screen.ADD_REMOTE;
        } else if (saved.hasAuth()) {
            connectionsScreen.startReconnectPrompt(saved);
        } else {
            connectToRemote(saved.alias(), saved.host(), saved.port(), null, null);
        }
    }

    private EventResult handleReconnectPromptKey(KeyEvent event) {
        if (event.isCancel()) {
            connectionsScreen.cancelReconnectPrompt();
            return EventResult.HANDLED;
        }
        if (event.isUp() || event.isDown()) {
            connectionsScreen.promptToggleFocus();
            return EventResult.HANDLED;
        }
        if (event.isDeleteBackward()) {
            connectionsScreen.promptHandleBackspace();
            return EventResult.HANDLED;
        }
        if (event.isConfirm()) {
            if (connectionsScreen.promptIsOnLastField()) {
                var target = connectionsScreen.promptTarget();
                connectToRemote(target.alias(), target.host(), target.port(),
                        connectionsScreen.promptUsername(), connectionsScreen.promptPassword());
                connectionsScreen.cancelReconnectPrompt();
            } else {
                connectionsScreen.promptToggleFocus();
            }
            return EventResult.HANDLED;
        }
        int c = event.codePoint();
        if (c >= 32 && c < 127) {
            connectionsScreen.promptHandleChar((char) c);
            return EventResult.HANDLED;
        }
        return EventResult.UNHANDLED;
    }

    private EventResult handleAddRemoteKey(KeyEvent event) {
        if (event.isCancel()) {
            connectError = null;
            currentScreen = Screen.CONNECTIONS;
            return EventResult.HANDLED;
        }
        if (event.isUp()) {
            addRemoteScreen.focusPrevious();
            return EventResult.HANDLED;
        }
        if (event.isDown()) {
            addRemoteScreen.focusNext();
            return EventResult.HANDLED;
        }
        if (addRemoteScreen.focused() == AddRemoteDialogScreen.Field.AUTH
                && (event.isLeft() || event.isRight())) {
            addRemoteScreen.toggleAuth();
            return EventResult.HANDLED;
        }
        if (addRemoteScreen.focused() == AddRemoteDialogScreen.Field.METHOD
                && (event.isLeft() || event.isRight())) {
            addRemoteScreen.toggleMethod();
            return EventResult.HANDLED;
        }
        if (addRemoteScreen.focused() == AddRemoteDialogScreen.Field.SSH_AUTH_TYPE
                && (event.isLeft() || event.isRight())) {
            addRemoteScreen.toggleSshAuthType();
            return EventResult.HANDLED;
        }
        if (event.isDeleteBackward()) {
            addRemoteScreen.handleBackspace();
            return EventResult.HANDLED;
        }
        if (event.isConfirm()) {
            if (addRemoteScreen.isOnLastField()) {
                connectError = null;
                if (addRemoteScreen.isEditMode()) {
                    addRemoteScreen.submit(this::updateSavedConnection);
                } else {
                    addRemoteScreen.submit(this::connectFromRequest);
                }
            } else {
                addRemoteScreen.focusNext();
            }
            return EventResult.HANDLED;
        }
        int c = event.codePoint();
        if (c >= 32 && c < 127) {
            addRemoteScreen.handleChar((char) c);
            return EventResult.HANDLED;
        }
        return EventResult.UNHANDLED;
    }

    // Edit path: persists the metadata change directly, no live connect
    // attempt (unlike Add, which connects first and saves as a side effect).
    private void updateSavedConnection(AddRemoteDialogScreen.ConnectRequest request) {
        String editId = addRemoteScreen.editId();
        CompletableFuture.runAsync(() -> {
            String savedUsername = (request.username() != null && !request.username().isBlank()) ? request.username() : "";
            var updatedConn = new SavedConnection(editId, request.alias(), request.host(), request.port(), savedUsername,
                    request.method(), request.sshPort(), request.sshKeyPath() != null ? request.sshKeyPath() : "", request.rmiPort());
            var path = SavedConnectionsStore.defaultPath();
            var updated = SavedConnectionsStore.update(SavedConnectionsStore.load(path), updatedConn);
            SavedConnectionsStore.save(path, updated);
            connectionsScreen.setSavedConnections(updated);
            currentScreen = Screen.CONNECTIONS;
        });
    }

    // m/t/g/c are now handled globally in handleKeyEvent() (any metrics screen
    // reachable from any other) — only esc's disconnect is Overview-specific.
    private EventResult handleOverviewKey(KeyEvent event) {
        if (event.isCancel()) {
            disconnect();
            return EventResult.HANDLED;
        }
        return EventResult.UNHANDLED;
    }

    // Shared by Memory/Threads/GC Log/Classes — esc goes back one level to
    // Overview (not a disconnect, unlike Overview's own esc handler).
    private EventResult handleDetailScreenKey(KeyEvent event) {
        if (event.isCancel()) {
            currentScreen = Screen.OVERVIEW;
            return EventResult.HANDLED;
        }
        // Classes' histogram is on-demand only (never polled — see
        // MetricsSource.fetchClassHistogram()), so it needs its own trigger.
        if (currentScreen == Screen.CLASSES && event.isChar('r') && classesScreen != null) {
            classesScreen.refresh();
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
                memoryScreen = new MemoryScreen(source);
                threadsScreen = new ThreadsScreen(source);
                gcLogScreen = new GcLogScreen(source);
                classesScreen = new ClassesScreen(source);
                connectError = null;
                currentScreen = Screen.OVERVIEW;
            } catch (ConnectionException e) {
                connectError = e.getMessage();
            }
        });
    }

    // Docker containers are discovered fresh each time, like local processes —
    // connect directly, no saved-profile step (that's REMOTES's job).
    private void connectToSelectedDocker() {
        DockerContainerInfo container = connectionsScreen.selectedDocker();
        if (container == null) {
            return;
        }
        CompletableFuture.runAsync(() -> {
            try {
                var connection = new RemoteJmxConnection("localhost", container.registryPort(), null, null, container.name());
                var source = new JmxPollingMetricsSource();
                source.start(connection);
                metricsSource = source;
                overviewScreen = new OverviewScreen(source);
                memoryScreen = new MemoryScreen(source);
                threadsScreen = new ThreadsScreen(source);
                gcLogScreen = new GcLogScreen(source);
                classesScreen = new ClassesScreen(source);
                connectError = null;
                currentScreen = Screen.OVERVIEW;
            } catch (ConnectionException e) {
                connectError = e.getMessage();
            }
        });
    }

    private void connectToRemote(String alias, String host, int port, String username, String password) {
        connectAndSave(() -> new RemoteJmxConnection(host, port, username, password, alias),
                new SavedConnection(alias, host, port, (username != null && !username.isBlank()) ? username : "",
                        SavedConnection.METHOD_DIRECT_REMOTE_JMX));
    }

    // Add Remote form submit — dispatches to the ConnectionHandle impl for
    // the chosen method (only two dispatch sites exist today: this switch
    // and updateSavedConnection's metadata-only persistence, see
    // docs/specs/architecture.md's Connection Layer section).
    private void connectFromRequest(AddRemoteDialogScreen.ConnectRequest request) {
        String savedUsername = (request.username() != null && !request.username().isBlank()) ? request.username() : "";
        SavedConnection toSave = switch (request.method()) {
            case SavedConnection.METHOD_SSH_TUNNEL -> new SavedConnection(request.alias(), request.host(), request.port(),
                    savedUsername, request.method(), request.sshPort(),
                    request.sshKeyPath() != null ? request.sshKeyPath() : "", request.rmiPort());
            default -> new SavedConnection(request.alias(), request.host(), request.port(), savedUsername, request.method());
        };
        connectAndSave(() -> switch (request.method()) {
            case SavedConnection.METHOD_SSH_TUNNEL -> new SshTunnelConnection(request.host(), request.sshPort(),
                    request.username(), request.password(), request.sshKeyPath(), request.sshPassphrase(),
                    request.port(), request.rmiPort(), request.alias());
            default -> new RemoteJmxConnection(request.host(), request.port(), request.username(), request.password(), request.alias());
        }, toSave);
    }

    private void connectAndSave(java.util.function.Supplier<ConnectionHandle> connector, SavedConnection toSave) {
        CompletableFuture.runAsync(() -> {
            try {
                var connection = connector.get();
                var source = new JmxPollingMetricsSource();
                source.start(connection);
                metricsSource = source;
                overviewScreen = new OverviewScreen(source);
                memoryScreen = new MemoryScreen(source);
                threadsScreen = new ThreadsScreen(source);
                gcLogScreen = new GcLogScreen(source);
                classesScreen = new ClassesScreen(source);
                connectError = null;
                currentScreen = Screen.OVERVIEW;

                var path = SavedConnectionsStore.defaultPath();
                var updated = SavedConnectionsStore.upsert(SavedConnectionsStore.load(path), toSave);
                SavedConnectionsStore.save(path, updated);
                connectionsScreen.setSavedConnections(updated);
            } catch (ConnectionException e) {
                connectError = e.getMessage();
            }
        });
    }

    private void disconnect() {
        releaseMetrics();
        currentScreen = Screen.CONNECTIONS;
        refreshProcesses();
        refreshDockerContainers();
    }

    private void releaseMetrics() {
        MetricsSource source = metricsSource;
        if (source != null) {
            source.close();
            metricsSource = null;
        }
        overviewScreen = null;
        memoryScreen = null;
        threadsScreen = null;
        gcLogScreen = null;
        classesScreen = null;
    }

    public static void main(String[] args) throws Exception {
        var app = new JvmMonitorTui();
        // Safety net for Ctrl+C/SIGTERM/any exit path that bypasses the key
        // handler — the 'q' path already closes metricsSource in handleKeyEvent.
        Runtime.getRuntime().addShutdownHook(new Thread(app::releaseMetrics));
        app.run();
    }
}
