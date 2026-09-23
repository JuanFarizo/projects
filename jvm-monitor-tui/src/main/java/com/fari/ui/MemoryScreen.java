package com.fari.ui;

import com.fari.metrics.BuffersSnapshot;
import com.fari.metrics.ConnectionStatus;
import com.fari.metrics.HeapSnapshot;
import com.fari.metrics.MetricsSnapshot;
import com.fari.metrics.MetricsSource;
import com.fari.metrics.NonHeapSnapshot;
import dev.tamboui.style.Style;
import dev.tamboui.toolkit.element.Element;
import dev.tamboui.widgets.barchart.Bar;

import java.util.Locale;

import static dev.tamboui.toolkit.Toolkit.*;

/**
 * Memory detail: full-width Heap chart, non-heap pool breakdown, off-heap
 * buffer pools. Reached from Overview via 'm'.
 */
public final class MemoryScreen {

    private final MetricsSource metricsSource;

    public MemoryScreen(MetricsSource metricsSource) {
        this.metricsSource = metricsSource;
    }

    public Element render() {
        MetricsSnapshot snapshot = metricsSource.snapshot();

        if (snapshot.status() == ConnectionStatus.DISCONNECTED) {
            return column(
                    text(" MEMORY").fg(Theme.TEXT_PRIMARY).bold(),
                    panel("",
                            text(" Connection lost: " + snapshot.errorMessage()).fg(Theme.STATUS_BAD).bold()
                    ).rounded().borderColor(Theme.STATUS_BAD).padding(1)
            ).id("memory-screen");
        }

        return column(
                text(" MEMORY").fg(Theme.TEXT_PRIMARY).bold(),
                heapPanel(snapshot.heap()),
                nonHeapPanel(snapshot.heap(), snapshot.nonHeap()),
                buffersPanel(snapshot.buffers())
        ).id("memory-screen");
    }

    private Element heapPanel(HeapSnapshot heap) {
        return panel("HEAP MEMORY",
                OverviewScreen.heapChart(heap).fill()
        ).rounded().borderColor(Theme.BORDER).padding(1).fill();
    }

    private Element nonHeapPanel(HeapSnapshot heap, NonHeapSnapshot nonHeap) {
        // Horizontal, not vertical: vertical bars default to 1-column width,
        // which truncates every label to its first letter (Eden/Old/Survivor/
        return panel("NON-HEAP & POOLS",
                barChart()
                        .data(
                                Bar.of(heap.eden(), "Eden"),
                                Bar.of(heap.old(), "Old"),
                                Bar.of(heap.survivor(), "Survivor"),
                                Bar.of(nonHeap.codeCacheUsed(), "Code Cache"),
                                Bar.of(nonHeap.compressedClassSpaceUsed(), "Compr. Class Space")
                        )
                        .horizontal()
                        .barGap(1)
                        .barColor(Theme.ACCENT)
                        .labelStyle(Style.EMPTY.fg(Theme.TEXT_MUTED))
                        .valueStyle(Style.EMPTY.fg(Theme.TEXT_SECONDARY))
        ).rounded().borderColor(Theme.BORDER).padding(1).length(9);
    }

    private Element buffersPanel(BuffersSnapshot buffers) {
        return panel("OFF-HEAP BUFFERS",
                column(
                        bufferRow("Direct", buffers.direct()),
                        bufferRow("Mapped", buffers.mapped())
                )
        ).rounded().borderColor(Theme.BORDER).padding(1).length(6);
    }

    private Element bufferRow(String label, com.fari.metrics.BufferPoolSnapshot pool) {
        return text(String.format(Locale.ROOT, " %-7s count %d  used %s  capacity %s",
                label, pool.count(), format(pool.used()), format(pool.capacity())))
                .fg(Theme.TEXT_SECONDARY);
    }

    private static String format(long bytes) {
        double mb = bytes / (1024.0 * 1024.0);
        return String.format(Locale.ROOT, "%.1fMB", mb);
    }
}
