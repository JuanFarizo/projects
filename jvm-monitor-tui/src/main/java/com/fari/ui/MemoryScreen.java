package com.fari.ui;

import com.fari.metrics.BufferPoolSnapshot;
import com.fari.metrics.BuffersSnapshot;
import com.fari.metrics.ConnectionStatus;
import com.fari.metrics.HeapSnapshot;
import com.fari.metrics.MetricsSnapshot;
import com.fari.metrics.MetricsSource;
import com.fari.metrics.NonHeapSnapshot;
import com.fari.metrics.VmInfoSnapshot;
import dev.tamboui.style.Style;
import dev.tamboui.toolkit.element.Element;
import dev.tamboui.widgets.barchart.Bar;

import java.util.Locale;

import static dev.tamboui.toolkit.Toolkit.*;

/**
 * Memory detail: Heap chart and off-heap buffers side by side, non-heap pool
 * breakdown below. Reached from Overview via 'm'.
 */
public final class MemoryScreen {

    // DualSparkline/BarChart both under-report their own preferredSize(), and
    // Column.preferredSize() sums children's preferredSize() rather than
    // honoring their explicit constraint() — so an unconstrained wrapping
    // Column silently under-sizes itself and Panel gives it a too-small Rect.
    // Fix: give the leaf AND its wrapping Column an explicit .length().
    private static final int HEAP_SPARKLINE_HEIGHT = 12;
    private static final int BUFFER_SPARKLINE_HEIGHT = 8;
    private static final int SIDE_PANEL_HEIGHT = HEAP_SPARKLINE_HEIGHT + 6;

    // Above this ratio-to-ceiling, a pool is close enough to its cap to flag.
    private static final double HIGH_UTILIZATION_WARN_RATIO = 0.85;

    // Named so barsHeight below reads as a formula, not a magic number.
    private static final int NON_HEAP_BAR_COUNT = 5;
    private static final int NON_HEAP_BAR_GAP = 1;

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
                row(heapPanel(snapshot.heap()), buffersPanel(snapshot.vmInfo(), snapshot.buffers()))
                        .spacing(1).length(SIDE_PANEL_HEIGHT),
                nonHeapPanel(snapshot.heap(), snapshot.nonHeap())
        ).id("memory-screen");
    }

    // DualSparkline, not Chart (see metrics.md). Auto-scaled, not pinned to
    // heap.max() — pinning flattened the line under light load.
    private Element heapPanel(HeapSnapshot heap) {
        Element sparkline = dualSparkline(heap.usedHistory(), heap.committedHistory())
                .topStyle(Style.EMPTY.fg(Theme.ACCENT).bold()).bottomColor(Theme.TEXT_SECONDARY)
                .showYAxis(true).xLabels("-40s", "now")
                .length(HEAP_SPARKLINE_HEIGHT);

        return panel("HEAP MEMORY",
                column(
                        statRow("Used", format(heap.used()), "Committed", format(heap.committed()), "Max", format(heap.max())),
                        sparkline
                ).spacing(1).length(HEAP_SPARKLINE_HEIGHT + 2)
        ).rounded().borderColor(Theme.BORDER).padding(1).fill(1);
    }

    private static Element statRow(String label1, String value1, String label2, String value2, String label3, String value3) {
        return row(
                text(label1 + " ").fg(Theme.TEXT_MUTED), text(value1 + "   ").fg(Theme.TEXT_PRIMARY),
                text(label2 + " ").fg(Theme.TEXT_MUTED), text(value2 + "   ").fg(Theme.TEXT_PRIMARY),
                text(label3 + " ").fg(Theme.TEXT_MUTED), text(value3).fg(Theme.TEXT_PRIMARY)
        );
    }

    private Element nonHeapPanel(HeapSnapshot heap, NonHeapSnapshot nonHeap) {
        long maxUsed = java.util.stream.LongStream.of(
                heap.eden(), heap.old(), heap.survivor(),
                nonHeap.codeCacheUsed(), nonHeap.compressedClassSpaceUsed()
        ).max().orElse(0);
        // Explicit max above the real data max keeps every bar short of full width.
        long chartMax = Math.max(1, maxUsed + Math.max(2, maxUsed / 5));
        int barsHeight = NON_HEAP_BAR_COUNT + (NON_HEAP_BAR_COUNT - 1) * NON_HEAP_BAR_GAP;

        // Horizontal: vertical bars default to 1-column width, truncating
        // labels to their first letter.
        Element chart = barChart()
                .data(
                        memBar(heap.eden(), "Eden"),
                        memBar(heap.old(), "Old"),
                        memBar(heap.survivor(), "Survivor"),
                        memBar(nonHeap.codeCacheUsed(), "Code Cache"),
                        memBar(nonHeap.compressedClassSpaceUsed(), "Compr. Class Space")
                )
                .max(chartMax)
                .horizontal()
                .barGap(NON_HEAP_BAR_GAP)
                .barColor(Theme.ACCENT)
                .labelStyle(Style.EMPTY.fg(Theme.TEXT_MUTED))
                .valueStyle(Style.EMPTY.fg(Theme.TEXT_SECONDARY))
                // Explicit: BarChart's preferredSize() ignores barGap,
                // under-reporting height and clipping the last bars.
                .length(barsHeight);

        return panel("NON-HEAP & POOLS",
                column(
                        statRow("Used", format(nonHeap.used()), "Committed", format(nonHeap.committed()),
                                "Max", nonHeap.max() > 0 ? format(nonHeap.max()) : "no limit"),
                        chart,
                        codeCacheLine(nonHeap)
                ).spacing(1).length(barsHeight + 4)
        ).rounded().borderColor(Theme.BORDER).padding(1).length(barsHeight + 8);
    }

    private static Element codeCacheLine(NonHeapSnapshot nonHeap) {
        if (nonHeap.codeCacheMax() <= 0) {
            return text(String.format(Locale.ROOT, " Code Cache: %s / no limit", format(nonHeap.codeCacheUsed())))
                    .fg(Theme.TEXT_SECONDARY);
        }
        double ratio = (double) nonHeap.codeCacheUsed() / nonHeap.codeCacheMax();
        boolean high = ratio > HIGH_UTILIZATION_WARN_RATIO;
        var line = text(String.format(Locale.ROOT, " Code Cache: %s / %s (%.0f%%)",
                format(nonHeap.codeCacheUsed()), format(nonHeap.codeCacheMax()), ratio * 100))
                .fg(high ? Theme.STATUS_BAD : Theme.TEXT_SECONDARY);
        return high ? line.bold() : line;
    }

    // value() drives proportional height against chartMax;
    // textValue() overrides the displayed value with the formatted byte string.
    private static Bar memBar(long bytes, String label) {
        return Bar.builder().value(bytes).label(label).textValue(format(bytes)).build();
    }

    private Element buffersPanel(VmInfoSnapshot vmInfo, BuffersSnapshot buffers) {
        Element trend = dualSparkline(buffers.direct().usedHistory(), buffers.mapped().usedHistory())
                .topStyle(Style.EMPTY.fg(Theme.ACCENT).bold()).bottomColor(Theme.TEXT_SECONDARY)
                .showYAxis(true).xLabels("-40s", "now")
                .length(BUFFER_SPARKLINE_HEIGHT);

        int contentHeight = 3 + 3 + BUFFER_SPARKLINE_HEIGHT; // 3 text rows + 3 gaps + trend
        return panel("OFF-HEAP BUFFERS",
                column(
                        bufferRow("Direct", buffers.direct()),
                        bufferRow("Mapped", buffers.mapped()),
                        directMemoryLine(vmInfo, buffers.direct()),
                        trend
                ).spacing(1).length(contentHeight)
        ).rounded().borderColor(Theme.BORDER).padding(1).fill(1);
    }

    private static Element directMemoryLine(VmInfoSnapshot vmInfo, BufferPoolSnapshot direct) {
        if (!vmInfo.directMemorySupported() || vmInfo.maxDirectMemorySize() <= 0) {
            return text(" Direct memory limit: not set (JVM defaults to -Xmx)").fg(Theme.TEXT_MUTED);
        }
        double ratio = (double) direct.used() / vmInfo.maxDirectMemorySize();
        boolean high = ratio > HIGH_UTILIZATION_WARN_RATIO;
        var line = text(String.format(Locale.ROOT, " Direct memory: %s / %s (%.0f%%)",
                format(direct.used()), format(vmInfo.maxDirectMemorySize()), ratio * 100))
                .fg(high ? Theme.STATUS_BAD : Theme.TEXT_SECONDARY);
        return high ? line.bold() : line;
    }

    private Element bufferRow(String label, BufferPoolSnapshot pool) {
        return text(String.format(Locale.ROOT, " %-7s count %d  used %s  capacity %s",
                label, pool.count(), format(pool.used()), format(pool.capacity())))
                .fg(Theme.TEXT_SECONDARY);
    }

    // Adaptive KB/MB — plain MB rounded small buffer pools down to "0.0MB".
    private static String format(long bytes) {
        double kb = bytes / 1024.0;
        if (kb < 1024) {
            return String.format(Locale.ROOT, "%.1fKB", kb);
        }
        return String.format(Locale.ROOT, "%.1fMB", kb / 1024.0);
    }
}
