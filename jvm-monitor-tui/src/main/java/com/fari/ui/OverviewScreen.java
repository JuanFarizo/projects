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
import dev.tamboui.toolkit.elements.ChartElement;
import dev.tamboui.widgets.chart.Axis;
import dev.tamboui.widgets.chart.Dataset;
import dev.tamboui.widgets.chart.GraphType;
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

    // Sparkline, not the full Chart widget: the 2x2 Overview grid gives each
    // panel very little vertical room, and Chart's axis labels + legend eat
    // most of it, leaving almost nothing for the actual line. DualSparkline
    // keeps the used/committed comparison (top=used, bottom=committed) and
    // the X/Y reference labels, in a fraction of the height. The full Chart
    // (with axis titles and a proper legend) still lives on the Memory
    // detail screen, which has the room for it — see MemoryScreen.heapPanel.
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

    // Auto-scaled to the visible data (not fixed at the ceiling) — chosen
    // over metrics.md's original "Y-axis bound fixed at max" design because,
    // under normal/light load, that pinned the line to the bottom row and
    // made it look static. Trade-off accepted: the direct "how close to the
    // ceiling" read is gone; see docs/spec/metrics.md's Display philosophy,
    // due for an update to match once this is confirmed.
    static ChartElement heapChart(HeapSnapshot heap) {
        double[] bounds = autoYBounds(toDoubleArray(heap.usedHistory(), heap.committedHistory()));
        return chart()
                .dataset(Dataset.builder()
                        .name("used")
                        .data(toPoints(heap.usedHistory()))
                        .graphType(GraphType.LINE)
                        .marker(Dataset.Marker.BRAILLE)
                        .style(Style.EMPTY.fg(Theme.ACCENT))
                        .build())
                .dataset(Dataset.builder()
                        .name("committed")
                        .data(toPoints(heap.committedHistory()))
                        .graphType(GraphType.LINE)
                        .marker(Dataset.Marker.BRAILLE)
                        .style(Style.EMPTY.fg(Theme.TEXT_SECONDARY))
                        .build())
                .xAxis(Axis.builder()
                        .bounds(0, Math.max(1, heap.usedHistory().length - 1))
                        .labels("-40s", "now")
                        .build())
                .yAxis(Axis.builder()
                        .bounds(bounds[0], bounds[1])
                        .title("MB")
                        .labels(String.format(Locale.ROOT, "%.0f", bounds[0]),
                                String.format(Locale.ROOT, "%.0f", bounds[1]))
                        .build());
    }

    static double[][] toPoints(long[] history) {
        double[][] points = new double[history.length][];
        for (int i = 0; i < history.length; i++) {
            points[i] = new double[] {i, history[i]};
        }
        return points;
    }

    static double[] toDoubleArray(long[]... histories) {
        int total = 0;
        for (long[] h : histories) {
            total += h.length;
        }
        double[] out = new double[total];
        int i = 0;
        for (long[] h : histories) {
            for (long v : h) {
                out[i++] = v;
            }
        }
        return out;
    }

    // {min, max} padded 10% on each side; falls back to {0, 1} when there's
    // no data yet or the visible window is perfectly flat (avoids a
    // zero-height axis range).
    static double[] autoYBounds(double... values) {
        double min = Double.MAX_VALUE;
        double max = -Double.MAX_VALUE;
        for (double v : values) {
            min = Math.min(min, v);
            max = Math.max(max, v);
        }
        if (values.length == 0 || min > max) {
            return new double[] {0, 1};
        }
        if (min == max) {
            min = Math.max(0, min - 1);
            max = max + 1;
        }
        double pad = (max - min) * 0.1;
        return new double[] {Math.max(0, min - pad), max + pad};
    }


    // Sparkline, not Chart — same space rationale as heapPanel() above.
    // Sparkline's Y-axis label shows the raw data value, so the history is
    // pre-rounded to whole percent here (cpu.history() itself stays
    // tenths-of-a-percent for the text stat row's 1-decimal precision).
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
                ).spacing(1)
        ).rounded().borderColor(Theme.BORDER).padding(1);
    }

    // Rounding a lightly-loaded JVM's <0.5% samples straight to 0 made the
    // whole sparkline empty (every bar height 0, nothing visible) — floor
    // any real, nonzero load to at least 1% so the graph still shows
    // something instead of going blank on an idle target.
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

    // Both gauges are pure "how close to the ceiling" risk indicators (per
    // metrics.md's Display philosophy) — open FDs are Unix-only, so that
    // gauge is omitted entirely (not just blank) when unsupported.
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
