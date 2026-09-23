package com.fari;

import com.fari.connection.ConnectionException;
import com.fari.connection.LocalAttachConnection;
import com.fari.connection.LocalProcessInfo;
import com.fari.connection.ProcessDiscovery;
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
    // Debug aid, toggled by 'd': fakes a deadlock (with a full wait-for chain,
    // same shape as real DeadlockedThread data) so the banner/panel can be
    // exercised without triggering a real one. Scoped to display only — it
    // does not alter what ThreadsScreen reads from real metrics.
    private volatile boolean deadlockDemo = false;
    private static final List<DeadlockedThread> DEMO_DEADLOCK = List.of(
            new DeadlockedThread(-1, "demo-worker-1", "java.lang.Object", "demo-worker-2"),
            new DeadlockedThread(-2, "demo-worker-2", "java.lang.Object", "demo-worker-1")
    );
    // Thread IDs (sorted) of the deadlock the user last dismissed with 'x'.
    // Banner stays hidden while the same set persists; reappears once the set
    // changes (new/different incident) or clears (resolved, reset to null).
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
        // Footer legend is all metrics-screen navigation — meaningless before
        // a JVM is attached, so it only shows once metricsSource is set.
        if (metricsSource != null) {
            children.add(globalFooter());
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
                key("[n]", currentScreen == Screen.ADD_REMOTE), label("add remote", currentScreen == Screen.ADD_REMOTE),
                text(" |  ").fg(Theme.TEXT_MUTED),
                key("[esc]", false), label("back", false),
                key("[q]", false), label("quit", false),
                spacer()
        ).length(1);
    }

    // `active` highlights the entry for currentScreen so the footer legend
    // doubles as a "you are here" indicator.
    private static Element key(String k, boolean active) {
        return active
                ? text(k).fg(Theme.ACCENT).bold()
                : text(k).fg(Theme.TEXT_PRIMARY);
    }

    private static Element label(String l, boolean active) {
        return text(":" + l + "  ").fg(active ? Theme.ACCENT : Theme.TEXT_MUTED);
    }

    // Prepended above every screen's own content except THREADS (which already
    // shows the full deadlock panel — see ThreadsScreen.deadlockPanel). Naturally
    // absent pre-connect (or once disconnected) since ThreadSnapshot.empty()'s
    // deadlockedThreads() is empty, so no extra gating is needed for that case.
    private Element deadlockBanner() {
        if (currentScreen == Screen.THREADS) {
            return null;
        }
        List<DeadlockedThread> deadlockedThreads = currentDeadlockedThreads();
        if (deadlockedThreads.isEmpty()) {
            // Resolved (or never happened) — clear any stale dismissal so a
            // future incident, even one that reuses thread IDs, isn't muted.
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

    // Real deadlocked threads, or the 'd' demo fake when there are none.
    private List<DeadlockedThread> currentDeadlockedThreads() {
        MetricsSource source = metricsSource;
        if (source == null) {
            return List.of();
        }
        List<DeadlockedThread> threads = source.snapshot().threads().deadlockedThreads();
        return threads.isEmpty() && deadlockDemo ? DEMO_DEADLOCK : threads;
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
        // Global, reserved on every screen per the footer legend — '1'/'2'
        // jump straight to Connections/Overview instead of only being
        // reachable by backing out one level at a time.
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
        if (event.isChar('d')) {
            if (metricsSource != null) {
                deadlockDemo = !deadlockDemo;
            }
            return EventResult.HANDLED;
        }
        if (event.isChar('x')) {
            dismissDeadlockBanner();
            return EventResult.HANDLED;
        }
        // Global like '1'/'2' — jump straight to any metrics screen from any
        // other one, instead of only being reachable by backing out to
        // Overview first (see globalFooter(), same legend advertises these).
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

        return switch (currentScreen) {
            case CONNECTIONS -> handleConnectionsKey(event);
            case ADD_REMOTE -> handleAddRemoteKey(event);
            case OVERVIEW -> handleOverviewKey(event);
            case MEMORY, THREADS, GC_LOG, CLASSES -> handleDetailScreenKey(event);
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
