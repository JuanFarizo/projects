package com.fari.ui;

import com.fari.metrics.ClassesSnapshot;
import com.fari.metrics.ConnectionStatus;
import com.fari.metrics.MetricsSnapshot;
import com.fari.metrics.MetricsSource;
import dev.tamboui.style.Style;
import dev.tamboui.toolkit.element.Element;
import dev.tamboui.widgets.chart.Axis;
import dev.tamboui.widgets.chart.Dataset;
import dev.tamboui.widgets.chart.GraphType;

import java.util.Locale;

import static dev.tamboui.toolkit.Toolkit.*;

/**
 * Classes / Metaspace detail: used/committed history + loaded/unloaded
 * counts. No per-class table this pass — feasibility (diagnostic-command
 * MBeans) is still an open item in docs/spec/open-questions.md; building a
 * table against placeholder data would misrepresent that as resolved.
 * Reached from Overview via 'c'.
 */
public final class ClassesScreen {

    private final MetricsSource metricsSource;

    public ClassesScreen(MetricsSource metricsSource) {
        this.metricsSource = metricsSource;
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
                metaspacePanel(classes),
                countsPanel(classes)
        ).id("classes-screen");
    }

    // Auto-scaled to visible data — same rationale as OverviewScreen.heapChart().
    private Element metaspacePanel(ClassesSnapshot classes) {
        double[] bounds = OverviewScreen.autoYBounds(
                OverviewScreen.toDoubleArray(classes.usedHistory(), classes.committedHistory()));
        return panel("METASPACE",
                chart()
                        .dataset(Dataset.builder()
                                .name("used")
                                .data(toPoints(classes.usedHistory()))
                                .graphType(GraphType.LINE)
                                .marker(Dataset.Marker.BRAILLE)
                                .style(Style.EMPTY.fg(Theme.ACCENT))
                                .build())
                        .dataset(Dataset.builder()
                                .name("committed")
                                .data(toPoints(classes.committedHistory()))
                                .graphType(GraphType.LINE)
                                .marker(Dataset.Marker.BRAILLE)
                                .style(Style.EMPTY.fg(Theme.TEXT_SECONDARY))
                                .build())
                        .xAxis(Axis.builder()
                                .bounds(0, Math.max(1, classes.usedHistory().length - 1))
                                .labels("-40s", "now")
                                .build())
                        .yAxis(Axis.builder()
                                .bounds(bounds[0], bounds[1])
                                .title("MB")
                                .labels(String.format(Locale.ROOT, "%.0f", bounds[0]),
                                        String.format(Locale.ROOT, "%.0f", bounds[1]))
                                .build())
                        .fill()
        ).rounded().borderColor(Theme.BORDER).padding(1).fill();
    }

    private Element countsPanel(ClassesSnapshot classes) {
        return panel("LOADED CLASSES",
                text(String.format(Locale.ROOT, " Loaded %d   Unloaded %d",
                        classes.loaded(), classes.unloaded())).fg(Theme.TEXT_SECONDARY)
        ).rounded().borderColor(Theme.BORDER).padding(1).length(5);
    }

    private static double[][] toPoints(long[] history) {
        double[][] points = new double[history.length][];
        for (int i = 0; i < history.length; i++) {
            points[i] = new double[] {i, history[i]};
        }
        return points;
    }
}
