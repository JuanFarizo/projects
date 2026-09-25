package com.fari.ui;

import com.fari.metrics.ConnectionStatus;
import com.fari.metrics.CpuSnapshot;
import com.fari.metrics.GcSnapshot;
import com.fari.metrics.HeapSnapshot;
import com.fari.metrics.MetricsSnapshot;
import com.fari.metrics.MetricsSource;
import com.fari.metrics.ThreadSnapshot;
import com.fari.metrics.VmInfoSnapshot;
import dev.tamboui.style.Style;
import dev.tamboui.toolkit.element.Element;
import dev.tamboui.widgets.table.Row;

import java.time.Duration;
import java.util.List;
import java.util.Locale;

import static dev.tamboui.toolkit.Toolkit.*;

/** Overview dashboard: 2x2 panel grid (Heap/CPU/GC/Threads) + VM Info strip. */
public final class OverviewScreen {

    private final MetricsSource metricsSource;

    public OverviewScreen(MetricsSource metricsSource) {
        this.metricsSource = metricsSource;
    }

    public Element render() {
        MetricsSnapshot snapshot = metricsSource.snapshot();

        if (snapshot.status() == ConnectionStatus.DISCONNECTED) {
            return column(
                    header(snapshot),
                    panel("",
                            text(" Connection lost: " + snapshot.errorMessage()).fg(Theme.STATUS_BAD).bold()
                    ).rounded().borderColor(Theme.STATUS_BAD).padding(1)
            ).id("overview-screen");
        }

        return column(
                header(snapshot),
                grid(
                        heapPanel(snapshot.heap()),
                        cpuPanel(snapshot.cpu()),
                        gcPanel(snapshot.gc()),
                        threadsPanel(snapshot.threads())
                ).gridSize(2, 2).gutter(1).fill(),
                vmInfoPanel(snapshot)
        ).id("overview-screen");
    }

    private Element header(MetricsSnapshot snapshot) {
        String status = snapshot.status() == ConnectionStatus.CONNECTED ? "● RUNNING" : "○ " + snapshot.status();
        var color = snapshot.status() == ConnectionStatus.CONNECTED ? Theme.STATUS_GOOD : Theme.TEXT_MUTED;
        return row(
                text(" " + snapshot.vmInfo().label()).fg(Theme.TEXT_PRIMARY).bold(),
                text("  " + snapshot.vmInfo().jvmVersion()).fg(Theme.TEXT_SECONDARY),
                text("  uptime " + formatUptime(snapshot.vmInfo().uptimeMillis())).fg(Theme.TEXT_SECONDARY),
                spacer(),
                text(status + " ").fg(color)
        ).length(1);
    }

    private Element heapPanel(HeapSnapshot heap) {
        return panel("HEAP MEMORY",
                column(
                        statRow("Used", format(heap.used()), "Committed", format(heap.committed()), "Max", format(heap.max())),
                        dualSparkline(heap.usedHistory(), heap.committedHistory())
                                .topStyle(Style.EMPTY.fg(Theme.ACCENT).bold()).bottomColor(Theme.TEXT_SECONDARY)
                                .showYAxis(true).xLabels("-40s", "now")
                                .fill(),
                        text("Eden " + format(heap.eden()) + "  Old " + format(heap.old())
                                + "  Survivor " + format(heap.survivor()))
                                .fg(Theme.TEXT_SECONDARY)
                ).spacing(1).fill()
        ).rounded().borderColor(Theme.BORDER).padding(1);
    }

    private Element cpuPanel(CpuSnapshot cpu) {
        return panel("CPU",
                column(
                        statRow("Process", String.format(Locale.ROOT, "%.1f%%", cpu.processLoad() * 100),
                                "System", String.format(Locale.ROOT, "%.1f%%", cpu.systemLoad() * 100),
                                "Cores", String.valueOf(cpu.cores())),
                        sparkline(cpuWholePercent(cpu.history()))
                                .autoMax().color(Theme.ACCENT)
                                .showYAxis(true).xLabels("-60s", "now")
                                .fill(),
                        text(String.format(Locale.ROOT, "Rolling avg %.1f%% 60s", cpu.rollingAvgPercent())).fg(Theme.TEXT_SECONDARY)
                ).spacing(1).fill()
        ).rounded().borderColor(Theme.BORDER).padding(1);
    }

    // Floors nonzero load to 1%: rounding <0.5% samples to 0 made the
    // sparkline blank on idle targets.
    private static long[] cpuWholePercent(long[] tenthsHistory) {
        long[] percent = new long[tenthsHistory.length];
        for (int i = 0; i < tenthsHistory.length; i++) {
            long v = tenthsHistory[i];
            percent[i] = v > 0 ? Math.max(1, Math.round(v / 10.0)) : 0;
        }
        return percent;
    }

    private Element gcPanel(GcSnapshot gc) {
        var rows = gc.collectors().stream()
                .map(c -> Row.from(c.name(), String.valueOf(c.count()), c.totalTimeMs() + "ms",
                        String.format(Locale.ROOT, "%.1fms", c.avgPauseMs())))
                .toList();
        return panel("GC ACTIVITY",
                table()
                        .header(Row.from("Collector", "Count", "Total", "Avg Pause"))
                        .rows(rows)
                        .widths(fill(), length(8), length(10), length(10))
        ).rounded().borderColor(Theme.BORDER).padding(1).length(8);
    }

    private Element threadsPanel(ThreadSnapshot threads) {
        var states = threads.stateCounts();
        return panel("THREADS",
                column(
                        table()
                                .header(Row.from("Live", "Daemon", "Peak", "Started"))
                                .rows(List.of(Row.from(
                                        String.valueOf(threads.live()),
                                        String.valueOf(threads.daemon()),
                                        String.valueOf(threads.peak()),
                                        String.valueOf(threads.started())
                                )))
                                .widths(fill(), fill(), fill(), fill()),
                        table()
                                .header(Row.from("RUNNABLE", "WAITING", "TIMED_WAITING", "BLOCKED"))
                                .rows(List.of(Row.from(
                                        String.valueOf(states.getOrDefault(Thread.State.RUNNABLE, 0)),
                                        String.valueOf(states.getOrDefault(Thread.State.WAITING, 0)),
                                        String.valueOf(states.getOrDefault(Thread.State.TIMED_WAITING, 0)),
                                        String.valueOf(states.getOrDefault(Thread.State.BLOCKED, 0))
                                )))
                                .widths(fill(), fill(), fill(), fill())
                )
        ).rounded().borderColor(Theme.BORDER).padding(1).length(8);
    }

    private Element vmInfoPanel(MetricsSnapshot snapshot) {
        var vmInfo = snapshot.vmInfo();
        return panel("VM INFO",
                column(
                        text(String.format(Locale.ROOT, " %s  |  GC: %s  |  VM args: %d  |  Classpath entries: %d",
                                vmInfo.jvmVersion(), vmInfo.gcAlgorithm(), vmInfo.vmArgCount(), vmInfo.classpathEntryCount()))
                                .fg(Theme.TEXT_SECONDARY),
                        vmInfoGaugeRow(vmInfo)
                ).spacing(1)
        ).rounded().borderColor(Theme.BORDER).padding(1).length(7);
    }

    // Both gauges are ceiling-risk indicators
    // FD gauge omitted entirely on non-Unix, not just blank.
    private Element vmInfoGaugeRow(VmInfoSnapshot vmInfo) {
        double swapTotal = (double) vmInfo.swapTotal();
        double swapUsed = swapTotal > 0 ? (swapTotal - vmInfo.swapFree()) / swapTotal : 0;
        Element swapGauge = lineGauge(clampRatio(swapUsed))
                .label(String.format(Locale.ROOT, "Swap %s free / %s ",
                        format(vmInfo.swapFree()), format(vmInfo.swapTotal())))
                .filledColor(Theme.ACCENT).doubleLine();

        if (!vmInfo.fileDescriptorsSupported()) {
            return row(swapGauge).spacing(2);
        }

        double fdMax = (double) vmInfo.maxFileDescriptorCount();
        double fdUsed = fdMax > 0 ? vmInfo.openFileDescriptorCount() / fdMax : 0;
        Element fdGauge = lineGauge(clampRatio(fdUsed))
                .label(String.format(Locale.ROOT, "FDs %d / %d ",
                        vmInfo.openFileDescriptorCount(), vmInfo.maxFileDescriptorCount()))
                .filledColor(Theme.ACCENT).doubleLine();

        return row(swapGauge, fdGauge).spacing(2);
    }

    private static double clampRatio(double ratio) {
        return Math.max(0, Math.min(1, ratio));
    }

    private static Element statRow(String label1, String value1, String label2, String value2, String label3, String value3) {
        return row(
                text(label1 + " ").fg(Theme.TEXT_MUTED), text(value1 + "   ").fg(Theme.TEXT_PRIMARY),
                text(label2 + " ").fg(Theme.TEXT_MUTED), text(value2 + "   ").fg(Theme.TEXT_PRIMARY),
                text(label3 + " ").fg(Theme.TEXT_MUTED), text(value3).fg(Theme.TEXT_PRIMARY)
        );
    }

    private static String format(long bytes) {
        double mb = bytes / (1024.0 * 1024.0);
        return String.format(Locale.ROOT, "%.1fMB", mb);
    }

    private static String formatUptime(long millis) {
        Duration d = Duration.ofMillis(millis);
        long hours = d.toHours();
        long minutes = d.toMinutesPart();
        long seconds = d.toSecondsPart();
        return String.format(Locale.ROOT, "%02d:%02d:%02d", hours, minutes, seconds);
    }
}
