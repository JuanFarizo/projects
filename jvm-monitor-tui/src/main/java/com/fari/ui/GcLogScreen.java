package com.fari.ui;

import com.fari.metrics.ConnectionStatus;
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
import dev.tamboui.widgets.table.Row;

import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

import static dev.tamboui.toolkit.Toolkit.*;

/**
 * GC pause-event log: scatter of individual pauses (young vs full), plus the
 * most recent pause. Reached from Overview via 'g'.
 */
public final class GcLogScreen {

    private static final DateTimeFormatter TIME_FORMAT =
            DateTimeFormatter.ofPattern("HH:mm:ss").withZone(ZoneId.systemDefault());

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
                pauseEventsPanel(gc),
                lastPausePanel(gc.lastPause())
        ).id("gc-log-screen");
    }

    private Element pauseEventsPanel(GcSnapshot gc) {
        GcPauseAvailability availability = gc.lastPause().availability();
        if (availability == GcPauseAvailability.UNAVAILABLE) {
            return panel("PAUSE EVENTS",
                    text(" GC pause detail is unavailable for this connection method.").fg(Theme.TEXT_MUTED)
            ).rounded().borderColor(Theme.BORDER).padding(1).fill();
        }
        if (gc.pauseHistory().isEmpty()) {
            return panel("PAUSE EVENTS",
                    text(" Waiting for the first GC event...").fg(Theme.TEXT_MUTED)
            ).rounded().borderColor(Theme.BORDER).padding(1).fill();
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

        return panel("PAUSE EVENTS (young vs full)",
                chart()
                        .dataset(Dataset.builder()
                                .name("young")
                                .data(youngPoints)
                                .graphType(GraphType.SCATTER)
                                .marker(Dataset.Marker.DOT)
                                .style(Style.EMPTY.fg(Theme.ACCENT))
                                .build())
                        .dataset(Dataset.builder()
                                .name("full")
                                .data(fullPoints)
                                .graphType(GraphType.SCATTER)
                                .marker(Dataset.Marker.DOT)
                                .style(Style.EMPTY.fg(Theme.STATUS_BAD))
                                .build())
                        .xAxis(Axis.builder()
                                .bounds(0, Math.max(1, maxX))
                                .title("time (s)")
                                .labels("0", String.format(Locale.ROOT, "%.0f", Math.max(1, maxX)))
                                .build())
                        .yAxis(Axis.builder()
                                .bounds(0, maxPauseMs)
                                .title("ms")
                                .labels("0", String.format(Locale.ROOT, "%.0f", maxPauseMs))
                                .build())
                        .fill()
        ).rounded().borderColor(Theme.BORDER).padding(1).fill();
    }

    private Element lastPausePanel(GcPauseEvent lastPause) {
        if (lastPause.availability() != GcPauseAvailability.AVAILABLE) {
            String message = lastPause.availability() == GcPauseAvailability.UNAVAILABLE
                    ? "unavailable for this connection method"
                    : "waiting for the first GC event...";
            return panel("LAST PAUSE",
                    text(" " + message).fg(Theme.TEXT_MUTED)
            ).rounded().borderColor(Theme.BORDER).padding(1).length(5);
        }

        // Header row + one data row, not a single run-on sentence — each
        // field gets its own column so values are easy to scan.
        return panel("LAST PAUSE",
                table()
                        .header(Row.from("Collector", "Duration", "Cause", "Generation", "Time"))
                        .rows(List.of(Row.from(
                                lastPause.gcName(),
                                lastPause.durationMs() + "ms",
                                lastPause.cause(),
                                lastPause.isFullGc() ? "full" : "young",
                                TIME_FORMAT.format(Instant.ofEpochMilli(lastPause.timestampMillis()))
                        )))
                        .widths(fill(), length(10), fill(), length(10), length(10))
        ).rounded().borderColor(Theme.BORDER).padding(1).length(6);
    }

}
