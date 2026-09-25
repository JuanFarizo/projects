package com.fari.ui;

import com.fari.metrics.ClassHistogramEntry;
import com.fari.metrics.ClassHistogramResult;
import com.fari.metrics.ClassesSnapshot;
import com.fari.metrics.ConnectionStatus;
import com.fari.metrics.MetricsSnapshot;
import com.fari.metrics.MetricsSource;
import dev.tamboui.style.Style;
import dev.tamboui.toolkit.element.Element;
import dev.tamboui.widgets.table.Row;

import java.util.List;
import java.util.Locale;
import java.util.concurrent.CompletableFuture;

import static dev.tamboui.toolkit.Toolkit.*;

/**
 * Classes / Metaspace detail. Histogram is never polled (see
 * MetricsSource.fetchClassHistogram()) — fetched only on refresh.
 * Reached from Overview via 'c'.
 */
public final class ClassesScreen {

    // Cap at biggest offenders — not a heap profiler (metrics.md non-goals).
    private static final int MAX_TABLE_ROWS = 30;

    // Sparkline preferredSize() under-reports height, and a wrapping Column
    // sums it instead of honoring .length() — both need it set explicitly.
    private static final int METASPACE_SPARKLINE_HEIGHT = 10;
    private static final int LOADED_SPARKLINE_HEIGHT = 4;
    // statRow + chart + ratio line, plus border/padding — same formula as
    // MemoryScreen.SIDE_PANEL_HEIGHT.
    private static final int SIDE_PANEL_HEIGHT = METASPACE_SPARKLINE_HEIGHT + 8;

    private static final double HIGH_UTILIZATION_WARN_RATIO = 0.85;

    private final MetricsSource metricsSource;
    private volatile ClassHistogramResult histogram = ClassHistogramResult.notLoaded();
    private volatile boolean loading = false;
    private volatile long lastRefreshedMillis = 0;

    public ClassesScreen(MetricsSource metricsSource) {
        this.metricsSource = metricsSource;
    }

    /** Triggers a background fetch; no-op if one is already in flight. */
    public void refresh() {
        if (loading) {
            return;
        }
        loading = true;
        CompletableFuture.runAsync(() -> {
            histogram = metricsSource.fetchClassHistogram();
            lastRefreshedMillis = System.currentTimeMillis();
            loading = false;
        });
    }

    public Element render() {
        MetricsSnapshot snapshot = metricsSource.snapshot();

        if (snapshot.status() == ConnectionStatus.DISCONNECTED) {
            return column(
                    text(" CLASSES / METASPACE").fg(Theme.TEXT_PRIMARY).bold(),
                    panel("",
                            text(" Connection lost: " + snapshot.errorMessage()).fg(Theme.STATUS_BAD).bold()
                    ).rounded().borderColor(Theme.STATUS_BAD).padding(1)
            ).id("classes-screen");
        }

        ClassesSnapshot classes = snapshot.classes();
        return column(
                text(" CLASSES / METASPACE").fg(Theme.TEXT_PRIMARY).bold(),
                row(metaspacePanel(classes), classLoadingPanel(classes)).spacing(1).length(SIDE_PANEL_HEIGHT),
                loadedClassesPanel()
        ).id("classes-screen");
    }

    // DualSparkline, not Chart — see metrics.md's Classes/Metaspace Display note.
    // Wider than classLoadingPanel (fill(2) vs fill(1)) — metaspace is the primary signal.
    private Element metaspacePanel(ClassesSnapshot classes) {
        Element usedChart = dualSparkline(classes.usedHistory(), classes.committedHistory())
                .topStyle(Style.EMPTY.fg(Theme.ACCENT).bold()).bottomColor(Theme.TEXT_SECONDARY)
                .showYAxis(true).xLabels("-40s", "now")
                .length(METASPACE_SPARKLINE_HEIGHT);

        return panel("METASPACE",
                column(
                        statRow("Used", format(classes.used()), "Committed", format(classes.committed()),
                                "Loaded", String.valueOf(classes.loaded()), "Unloaded", String.valueOf(classes.unloaded())),
                        usedChart,
                        metaspaceRatioLine(classes)
                ).spacing(1).length(METASPACE_SPARKLINE_HEIGHT + 4)
        ).rounded().borderColor(Theme.BORDER).padding(1).fill(2);
    }

    private Element classLoadingPanel(ClassesSnapshot classes) {
        Element loadedChart = sparkline(classes.loadedDeltaHistory())
                .autoMax().color(Theme.ACCENT)
                .showYAxis(true).xLabels("-40s", "now")
                .length(LOADED_SPARKLINE_HEIGHT);

        return panel("CLASS LOADING",
                column(
                        text(" new classes/tick").fg(Theme.TEXT_MUTED),
                        loadedChart
                ).spacing(1).length(LOADED_SPARKLINE_HEIGHT + 2)
        ).rounded().borderColor(Theme.BORDER).padding(1).fill(1);
    }

    private static Element metaspaceRatioLine(ClassesSnapshot classes) {
        if (classes.metaspaceMax() <= 0) {
            return text(String.format(Locale.ROOT, " Metaspace: %s / no limit (-XX:MaxMetaspaceSize unset)",
                    format(classes.used()))).fg(Theme.TEXT_SECONDARY);
        }
        double ratio = (double) classes.used() / classes.metaspaceMax();
        boolean high = ratio > HIGH_UTILIZATION_WARN_RATIO;
        var line = text(String.format(Locale.ROOT, " Metaspace: %s / %s (%.0f%%)",
                format(classes.used()), format(classes.metaspaceMax()), ratio * 100))
                .fg(high ? Theme.STATUS_BAD : Theme.TEXT_SECONDARY);
        return high ? line.bold() : line;
    }

    private Element loadedClassesPanel() {
        String refreshedSuffix = histogram.available() && lastRefreshedMillis > 0
                ? String.format(Locale.ROOT, ", refreshed %ds ago", (System.currentTimeMillis() - lastRefreshedMillis) / 1000)
                : "";
        return panel("LOADED CLASSES  (top " + MAX_TABLE_ROWS + " by size — press 'r' to " +
                        (histogram.available() ? "refresh" : "load") + refreshedSuffix + ")",
                histogramBody()
        ).rounded().borderColor(Theme.BORDER).padding(1).fill();
    }

    private Element histogramBody() {
        if (loading) {
            return text(" Fetching class histogram...").fg(Theme.TEXT_SECONDARY);
        }
        if (!histogram.available()) {
            String message = histogram.errorMessage() == null
                    ? " Not loaded yet — press 'r' to fetch (walks the target's heap, not automatic)."
                    : " Unavailable: " + histogram.errorMessage();
            return text(message).fg(histogram.errorMessage() == null ? Theme.TEXT_SECONDARY : Theme.STATUS_BAD);
        }

        List<ClassHistogramEntry> entries = histogram.entries();
        long totalInstances = entries.stream().mapToLong(ClassHistogramEntry::instances).sum();
        long totalBytes = entries.stream().mapToLong(ClassHistogramEntry::bytes).sum();
        var rows = entries.stream()
                .limit(MAX_TABLE_ROWS)
                .map(e -> Row.from(e.className(), String.valueOf(e.instances()), format(e.bytes())))
                .toList();
        Element table = table()
                .header(Row.from("Class name", "Instances", "Size"))
                .rows(rows)
                .widths(fill(), length(12), length(10));

        return column(
                text(String.format(Locale.ROOT, " %d classes, %d instances, %s total",
                        entries.size(), totalInstances, format(totalBytes))).fg(Theme.TEXT_SECONDARY), table
        ).spacing(1).fill();
    }

    private static Element statRow(String label1, String value1, String label2, String value2,
                                    String label3, String value3, String label4, String value4) {
        return row(
                text(label1 + " ").fg(Theme.TEXT_MUTED), text(value1 + "   ").fg(Theme.TEXT_PRIMARY),
                text(label2 + " ").fg(Theme.TEXT_MUTED), text(value2 + "   ").fg(Theme.TEXT_PRIMARY),
                text(label3 + " ").fg(Theme.TEXT_MUTED), text(value3 + "   ").fg(Theme.TEXT_PRIMARY),
                text(label4 + " ").fg(Theme.TEXT_MUTED), text(value4).fg(Theme.TEXT_PRIMARY)
        );
    }

    private static String format(long bytes) {
        double mb = bytes / (1024.0 * 1024.0);
        return String.format(Locale.ROOT, "%.1fMB", mb);
    }
}
