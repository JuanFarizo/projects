package com.fari.ui;

import com.fari.metrics.ConnectionStatus;
import com.fari.metrics.GcCollectorStat;
import com.fari.metrics.GcPauseAvailability;
import com.fari.metrics.GcPauseEvent;
import com.fari.metrics.GcSnapshot;
import com.fari.metrics.MetricsSnapshot;
import com.fari.metrics.MetricsSource;
import dev.tamboui.style.Style;
import dev.tamboui.toolkit.element.Element;
import dev.tamboui.widgets.chart.Axis;
import dev.tamboui.widgets.chart.Dataset;
import dev.tamboui.widgets.chart.GraphType;
import dev.tamboui.widgets.table.Cell;
import dev.tamboui.widgets.table.Row;

import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.stream.Collectors;

import static dev.tamboui.toolkit.Toolkit.*;

/**
 * GC pause-event log: one bar per pause (young vs full), pause-latency stats,
 * per-collector totals, plus the most recent pause. Reached from Overview via 'g'.
 */
public final class GcLogScreen {

    private static final DateTimeFormatter TIME_FORMAT =
            DateTimeFormatter.ofPattern("HH:mm:ss").withZone(ZoneId.systemDefault());

    // Above this share of full GCs in the visible history, G1/Parallel are
    // typically under heap pressure rather than just doing routine young GCs.
    private static final double FULL_GC_WARN_RATIO = 0.25;

    // Relative to the collector's own average, not a fixed ms cutoff —
    // no such absolute threshold exists elsewhere in this codebase.
    private static final double PAUSE_OUTLIER_MULTIPLIER = 1.5;

    private final MetricsSource metricsSource;

    public GcLogScreen(MetricsSource metricsSource) {
        this.metricsSource = metricsSource;
    }

    public Element render() {
        MetricsSnapshot snapshot = metricsSource.snapshot();

        if (snapshot.status() == ConnectionStatus.DISCONNECTED) {
            return column(
                    text(" GC LOG").fg(Theme.TEXT_PRIMARY).bold(),
                    panel("",
                            text(" Connection lost: " + snapshot.errorMessage()).fg(Theme.STATUS_BAD).bold()
                    ).rounded().borderColor(Theme.STATUS_BAD).padding(1)
            ).id("gc-log-screen");
        }

        GcSnapshot gc = snapshot.gc();
        return column(
                text(" GC LOG").fg(Theme.TEXT_PRIMARY).bold(),
                row(pauseEventsPanel(gc), statsPanel(gc)).spacing(1).fill(),
                collectorsPanel(gc, snapshot.vmInfo().uptimeMillis()),
                lastPausePanel(gc)
        ).id("gc-log-screen");
    }

    private Element collectorsPanel(GcSnapshot gc, long uptimeMillis) {
        if (gc.collectors().isEmpty()) {
            return panel("COLLECTORS",
                    text(" No collector data available.").fg(Theme.TEXT_MUTED)
            ).rounded().borderColor(Theme.BORDER).padding(1).length(6);
        }

        long totalGcTimeMs = gc.collectors().stream().mapToLong(GcCollectorStat::totalTimeMs).sum();
        double overheadPct = uptimeMillis > 0 ? (100.0 * totalGcTimeMs / uptimeMillis) : 0.0;

        List<Row> rows = new ArrayList<>();
        for (GcCollectorStat stat : gc.collectors()) {
            rows.add(Row.from(
                    stat.name(),
                    Long.toString(stat.count()),
                    stat.totalTimeMs() + "ms",
                    String.format(Locale.ROOT, "%.1fms", stat.avgPauseMs())
            ));
        }

        return panel(String.format(Locale.ROOT, "COLLECTORS (%.2f%% of uptime in GC)", overheadPct),
                table()
                        .header(Row.from("Collector", "Count", "Total Time", "Avg Pause"))
                        .rows(rows)
                        .widths(fill(), length(10), length(12), length(12))
        ).rounded().borderColor(Theme.BORDER).padding(1).length(3 + rows.size());
    }

    private Element pauseEventsPanel(GcSnapshot gc) {
        GcPauseAvailability availability = gc.lastPause().availability();
        if (availability == GcPauseAvailability.UNAVAILABLE) {
            return panel("PAUSE EVENTS",
                    text(" GC pause detail is unavailable for this connection method.").fg(Theme.TEXT_MUTED)
            ).rounded().borderColor(Theme.BORDER).padding(1).fill(2);
        }
        if (gc.pauseHistory().isEmpty()) {
            return panel("PAUSE EVENTS",
                    text(" Waiting for the first GC event...").fg(Theme.TEXT_MUTED)
            ).rounded().borderColor(Theme.BORDER).padding(1).fill(2);
        }

        List<double[]> youngPoints = new ArrayList<>();
        List<double[]> fullPoints = new ArrayList<>();
        long firstTimestamp = gc.pauseHistory().get(0).timestampMillis();
        double maxPauseMs = 1;
        for (GcPauseEvent event : gc.pauseHistory()) {
            double x = (event.timestampMillis() - firstTimestamp) / 1000.0;
            double y = event.durationMs();
            maxPauseMs = Math.max(maxPauseMs, y);
            (event.isFullGc() ? fullPoints : youngPoints).add(new double[] {x, y});
        }
        double maxX = (gc.pauseHistory().get(gc.pauseHistory().size() - 1).timestampMillis() - firstTimestamp) / 1000.0;

        // Counts in the title so an empty "full" series reads as "no full GC
        // yet" (normal under light load) rather than looking broken.
        return panel(String.format(Locale.ROOT, "PAUSE EVENTS (young %d vs full %d)",
                        youngPoints.size(), fullPoints.size()),
                chart()
                        // BAR, not SCATTER: a floating dot has no baseline, so its
                        // height is hard to read against the axis at a glance.
                        .dataset(Dataset.builder()
                                .name("young")
                                .data(youngPoints)
                                .graphType(GraphType.BAR)
                                .style(Style.EMPTY.fg(Theme.ACCENT))
                                .build())
                        .dataset(Dataset.builder()
                                .name("full")
                                .data(fullPoints)
                                .graphType(GraphType.BAR)
                                .style(Style.EMPTY.fg(Theme.STATUS_BAD))
                                .build())
                        // No .title(): Chart's axis-title column is 1 char wide and
                        // wraps text letter-per-line — units folded into labels instead.
                        .xAxis(Axis.builder()
                                .bounds(0, Math.max(1, maxX))
                                .labels("0s", String.format(Locale.ROOT, "%.0fs", Math.max(1, maxX)))
                                .build())
                        .yAxis(Axis.builder()
                                .bounds(0, maxPauseMs)
                                .labels("0ms", String.format(Locale.ROOT, "%.0fms", maxPauseMs))
                                .build())
                        .fill()
        ).rounded().borderColor(Theme.BORDER).padding(1).fill(2);
    }

    private Element statsPanel(GcSnapshot gc) {
        List<GcPauseEvent> history = gc.pauseHistory();
        if (gc.lastPause().availability() == GcPauseAvailability.UNAVAILABLE || history.isEmpty()) {
            return panel("PAUSE STATS",
                    text(" No pause data yet.").fg(Theme.TEXT_MUTED)
            ).rounded().borderColor(Theme.BORDER).padding(1).fill(1);
        }

        List<Long> sortedDurations = history.stream()
                .map(GcPauseEvent::durationMs)
                .sorted()
                .toList();
        long p50 = percentile(sortedDurations, 0.50);
        long p95 = percentile(sortedDurations, 0.95);
        long max = sortedDurations.get(sortedDurations.size() - 1);

        long fullCount = history.stream().filter(GcPauseEvent::isFullGc).count();
        double fullRatio = (double) fullCount / history.size();
        boolean fullRatioHigh = fullRatio > FULL_GC_WARN_RATIO;

        long lastTimestamp = history.get(history.size() - 1).timestampMillis();
        long sinceLastMs = System.currentTimeMillis() - lastTimestamp;
        long avgIntervalMs = history.size() > 1
                ? (lastTimestamp - history.get(0).timestampMillis()) / (history.size() - 1)
                : 0;

        Map<String, Long> causeCounts = history.stream()
                .collect(Collectors.groupingBy(GcPauseEvent::cause, LinkedHashMap::new, Collectors.counting()));

        List<Element> lines = new ArrayList<>();
        lines.add(text(String.format(Locale.ROOT, " p50 %dms  p95 %dms  max %dms", p50, p95, max))
                .fg(Theme.TEXT_PRIMARY));
        var ratioLine = text(String.format(Locale.ROOT, " Full GC ratio: %.0f%%", fullRatio * 100))
                .fg(fullRatioHigh ? Theme.STATUS_BAD : Theme.TEXT_PRIMARY);
        lines.add(fullRatioHigh ? ratioLine.bold() : ratioLine);
        lines.add(text(String.format(Locale.ROOT, " Last GC: %ds ago, every ~%ds",
                        sinceLastMs / 1000, avgIntervalMs / 1000))
                .fg(Theme.TEXT_PRIMARY));
        lines.add(text(" Causes:").fg(Theme.TEXT_MUTED));
        for (Map.Entry<String, Long> entry : causeCounts.entrySet()) {
            lines.add(text(String.format(Locale.ROOT, "  %s x%d", entry.getKey(), entry.getValue()))
                    .fg(Theme.TEXT_PRIMARY));
        }

        return panel("PAUSE STATS", column(lines.toArray(Element[]::new)).spacing(1))
                .rounded().borderColor(Theme.BORDER).padding(1).fill(1);
    }

    private static long percentile(List<Long> sortedValues, double p) {
        int index = (int) Math.ceil(p * sortedValues.size()) - 1;
        index = Math.max(0, Math.min(sortedValues.size() - 1, index));
        return sortedValues.get(index);
    }

    private Element lastPausePanel(GcSnapshot gc) {
        GcPauseEvent lastPause = gc.lastPause();
        if (lastPause.availability() != GcPauseAvailability.AVAILABLE) {
            String message = lastPause.availability() == GcPauseAvailability.UNAVAILABLE
                    ? "unavailable for this connection method"
                    : "waiting for the first GC event...";
            return panel("LAST PAUSE",
                    text(" " + message).fg(Theme.TEXT_MUTED)
            ).rounded().borderColor(Theme.BORDER).padding(1).length(5);
        }

        boolean outlier = gc.collectors().stream()
                .filter(c -> c.name().equals(lastPause.gcName()))
                .findFirst()
                .map(c -> lastPause.durationMs() > c.avgPauseMs() * PAUSE_OUTLIER_MULTIPLIER)
                .orElse(false);
        Style durationStyle = outlier ? Style.EMPTY.fg(Theme.STATUS_BAD).bold() : Style.EMPTY.fg(Theme.TEXT_PRIMARY);

        long reclaimedBytes = lastPause.heapBeforeBytes() - lastPause.heapAfterBytes();
        String reclaimed = String.format(Locale.ROOT, "%.1fMB", reclaimedBytes / (1024.0 * 1024.0));

        // Header row + one data row, not a single run-on sentence — each
        // field gets its own column so values are easy to scan.
        return panel("LAST PAUSE",
                table()
                        .header(Row.from("Collector", "Duration", "Reclaimed", "Cause", "Generation", "Time"))
                        .rows(List.of(Row.from(
                                Cell.from(lastPause.gcName()),
                                Cell.from(lastPause.durationMs() + "ms").style(durationStyle),
                                Cell.from(reclaimed),
                                Cell.from(lastPause.cause()),
                                Cell.from(lastPause.isFullGc() ? "full" : "young"),
                                Cell.from(TIME_FORMAT.format(Instant.ofEpochMilli(lastPause.timestampMillis())))
                        )))
                        .widths(fill(), length(10), length(11), fill(), length(10), length(10))
        ).rounded().borderColor(Theme.BORDER).padding(1).length(6);
    }

}
