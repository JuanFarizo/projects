package com.fari.ui;

import com.fari.metrics.ConnectionStatus;
import com.fari.metrics.DeadlockedThread;
import com.fari.metrics.MetricsSnapshot;
import com.fari.metrics.MetricsSource;
import com.fari.metrics.ThreadCpuStat;
import com.fari.metrics.ThreadSnapshot;
import dev.tamboui.style.Style;
import dev.tamboui.toolkit.element.Element;
import dev.tamboui.widgets.barchart.Bar;
import dev.tamboui.widgets.table.Row;

import java.time.Duration;
import java.util.Locale;

import static dev.tamboui.toolkit.Toolkit.*;

/**
 * Thread detail: full state breakdown, per-thread CPU top-N, deadlock
 * detail. Reached from Overview via 't'.
 */
public final class ThreadsScreen {

    private final MetricsSource metricsSource;

    public ThreadsScreen(MetricsSource metricsSource) {
        this.metricsSource = metricsSource;
    }

    public Element render() {
        MetricsSnapshot snapshot = metricsSource.snapshot();

        if (snapshot.status() == ConnectionStatus.DISCONNECTED) {
            return column(
                    text(" THREADS").fg(Theme.TEXT_PRIMARY).bold(),
                    panel("",
                            text(" Connection lost: " + snapshot.errorMessage()).fg(Theme.STATUS_BAD).bold()
                    ).rounded().borderColor(Theme.STATUS_BAD).padding(1)
            ).id("threads-screen");
        }

        ThreadSnapshot threads = snapshot.threads();
        var elements = new java.util.ArrayList<Element>();
        elements.add(text(" THREADS").fg(Theme.TEXT_PRIMARY).bold());
        if (!threads.deadlockedThreads().isEmpty()) {
            elements.add(deadlockPanel(threads));
        }
        elements.add(stateBreakdownPanel(threads));
        elements.add(topCpuPanel(threads));

        return column(elements.toArray(Element[]::new)).id("threads-screen");
    }

    // Bar count/gap for the state-breakdown chart below — named so the
    // chart's required height (see barsHeight()) reads as a formula, not a
    // hand-computed magic number that silently goes stale if either changes.
    private static final int STATE_BAR_COUNT = 4;
    private static final int STATE_BAR_GAP = 1;

    private Element stateBreakdownPanel(ThreadSnapshot threads) {
        var states = threads.stateCounts();
        long maxCount = states.values().stream().mapToLong(Integer::longValue).max().orElse(0);
        // Explicit max above the real data max keeps every bar short of full width.
        long chartMax = Math.max(1, maxCount + Math.max(2, maxCount / 5));

        int blockedCount = states.getOrDefault(Thread.State.BLOCKED, 0);
        Bar blockedBar = blockedCount > 0
                ? Bar.builder().value(blockedCount).label("BLOCKED").style(Style.EMPTY.fg(Theme.STATUS_BAD)).build()
                : Bar.of(blockedCount, "BLOCKED");

        int barsHeight = STATE_BAR_COUNT + (STATE_BAR_COUNT - 1) * STATE_BAR_GAP;
        int gapLine = 1;
        int countsRowHeight = 2;

        // Horizontal, not vertical — see MemoryScreen.nonHeapPanel()'s comment:
        // vertical bars truncate labels to 1 column ("RUNNABLE" -> "R").
        return panel("STATE BREAKDOWN",
                column(
                        threadCountsRow(threads),
                        text(""),
                        barChart()
                                .data(
                                        Bar.of(states.getOrDefault(Thread.State.RUNNABLE, 0), "RUNNABLE"),
                                        Bar.of(states.getOrDefault(Thread.State.WAITING, 0), "WAITING"),
                                        Bar.of(states.getOrDefault(Thread.State.TIMED_WAITING, 0), "TIMED_WAITING"),
                                        blockedBar
                                )
                                .max(chartMax)
                                .horizontal()
                                .barGap(STATE_BAR_GAP)
                                .barColor(Theme.ACCENT)
                                .labelStyle(Style.EMPTY.fg(Theme.TEXT_MUTED))
                                .valueStyle(Style.EMPTY.fg(Theme.TEXT_SECONDARY))
                                .length(barsHeight)
                )
                .length(countsRowHeight + gapLine + barsHeight)
        ).rounded().borderColor(Theme.BORDER).padding(1).length(countsRowHeight + gapLine + barsHeight + 4);
    }

    private Element threadCountsRow(ThreadSnapshot threads) {
        return row(
                statColumn("LIVE", threads.live()),
                text("   "),
                statColumn("DAEMON", threads.daemon()),
                text("   "),
                statColumn("PEAK", threads.peak()),
                text("   "),
                statColumn("STARTED", threads.started())
        ).length(2);
    }

    private static Element statColumn(String label, long value) {
        return column(
                text(label).fg(Theme.TEXT_MUTED),
                text(String.valueOf(value)).fg(Theme.TEXT_PRIMARY).bold()
        );
    }

    private Element topCpuPanel(ThreadSnapshot threads) {
        var rows = new java.util.ArrayList<Row>();
        int rank = 1;
        for (ThreadCpuStat stat : threads.topCpuThreads()) {
            Row row = Row.from(String.valueOf(rank), stat.name(), stat.state().name(),
                    formatCpuTime(stat.cpuTimeNanos()));
            // No row-divider primitive in TableElement — zebra-stripe alternate
            // rows instead, same "scannable" effect without one.
            if (rank % 2 == 0) {
                row = row.style(Style.EMPTY.bg(Theme.ROW_ALT));
            }
            rows.add(row);
            rank++;
        }
        return panel("TOP THREADS BY CPU",
                table()
                        .header(Row.from("#", "Thread", "State", "CPU Time"))
                        .rows(rows)
                        .widths(length(3), fill(), length(14), length(14))
        ).rounded().borderColor(Theme.BORDER).fill();
    }

    private Element deadlockPanel(ThreadSnapshot threads) {
        var deadlocked = threads.deadlockedThreads();
        var lines = new java.util.ArrayList<Element>();
        lines.add(text(" DEADLOCK DETECTED: " + deadlocked.size() + " threads").fg(Theme.STATUS_BAD).bold());
        for (DeadlockedThread dt : deadlocked) {
            String lock = dt.lockClassName() != null ? dt.lockClassName() : "unknown lock";
            String owner = dt.lockOwnerName() != null ? dt.lockOwnerName() : "unknown";
            lines.add(text(" \"" + dt.threadName() + "\" waiting on <" + lock + "> held by \"" + owner + "\"")
                    .fg(Theme.STATUS_BAD));
        }
        return panel("", column(lines.toArray(Element[]::new)))
                .rounded().borderColor(Theme.STATUS_BAD).padding(1).length(lines.size() + 4);
    }

    private static String formatCpuTime(long cpuTimeNanos) {
        Duration d = Duration.ofNanos(cpuTimeNanos);
        return String.format(Locale.ROOT, "%d.%02ds", d.toSeconds(), (d.toMillisPart() / 10));
    }
}
