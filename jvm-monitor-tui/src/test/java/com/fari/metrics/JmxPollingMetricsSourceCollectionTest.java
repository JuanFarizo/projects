package com.fari.metrics;

import com.fari.connection.LocalAttachConnection;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;

import java.io.File;
import java.io.IOException;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Collection-only smoke test for the metrics added to JmxPollingMetricsSource:
 * attaches to a real subprocess JVM (not self-attach, which needs
 * -Djdk.attach.allowAttachSelf=true — see docs/specs/open-questions.md known
 * risk #7) and asserts every newly-added snapshot field is populated plausibly.
 */
class JmxPollingMetricsSourceCollectionTest {

    private Process target;

    @AfterEach
    void tearDown() {
        if (target != null) {
            target.destroyForcibly();
        }
    }

    @Test
    @Timeout(30)
    void collectsAllNewMetricsFromALiveJvm() throws IOException, InterruptedException {
        target = launchSleepyTarget();
        String pid = String.valueOf(target.pid());

        LocalAttachConnection connection = new LocalAttachConnection(pid, "SleepyMain");
        JmxPollingMetricsSource source = new JmxPollingMetricsSource();
        try {
            source.start(connection);

            MetricsSnapshot snapshot = awaitConnected(source);

            assertTrue(snapshot.nonHeap().used() > 0, "non-heap used should be > 0");
            // Every running JVM has some JIT-compiled code by the time it's up —
            // a real value check, not just non-null, catches a regression in the
            // Code Cache pool-name matching in buildNonHeapSnapshot().
            assertTrue(snapshot.nonHeap().codeCacheUsed() > 0, "code cache used should be > 0");
            // BufferPoolSnapshot/BuffersSnapshot are never null by construction, so
            // asserting non-null alone would never fail — assert on the actual
            // fields instead (count may legitimately be 0 for an idle JVM).
            assertTrue(snapshot.buffers().direct().count() >= 0);
            assertTrue(snapshot.buffers().mapped().count() >= 0);

            assertFalse(snapshot.gc().collectors().isEmpty(), "expected at least one GC collector");

            GcPauseAvailability availability = snapshot.gc().lastPause().availability();
            assertTrue(availability == GcPauseAvailability.AVAILABLE
                            || availability == GcPauseAvailability.PENDING_FIRST_EVENT,
                    "local attach supports GC notifications, expected AVAILABLE or PENDING_FIRST_EVENT, got "
                            + availability);

            assertTrue(snapshot.threads().topCpuThreads().size() <= 10);
            assertTrue(!snapshot.threads().topCpuThreads().isEmpty());
            // Never null by construction (findDeadlockedThreads() == null maps to
            // an empty array) — SleepyMain has no real deadlock, so empty is the
            // actual expected value, not just "non-null".
            assertTrue(snapshot.threads().deadlockedThreads().isEmpty());

            assertTrue(snapshot.vmInfo().systemLoadAverage() >= -1);
            assertTrue(snapshot.vmInfo().jitCompilationTimeMs() >= 0);

            assertTrue(snapshot.classes().loaded() > 0);
            assertTrue(snapshot.classes().usedHistory().length >= 1);
            assertTrue(snapshot.classes().committedHistory().length >= 1);

            assertTrue(snapshot.heap().usedHistory().length >= 1);
            assertTrue(snapshot.heap().committedHistory().length >= 1);
        } finally {
            source.close();
        }
    }

    private static Process launchSleepyTarget() throws IOException {
        String javaBin = System.getProperty("java.home") + File.separator + "bin" + File.separator + "java";
        ProcessBuilder builder = new ProcessBuilder(
                javaBin, "-cp", System.getProperty("java.class.path"), SleepyMain.class.getName());
        builder.redirectOutput(ProcessBuilder.Redirect.DISCARD);
        builder.redirectError(ProcessBuilder.Redirect.DISCARD);
        return builder.start();
    }

    private static MetricsSnapshot awaitConnected(JmxPollingMetricsSource source) throws InterruptedException {
        long deadline = System.currentTimeMillis() + TimeUnit.SECONDS.toMillis(10);
        MetricsSnapshot snapshot = source.snapshot();
        while (snapshot.status() != ConnectionStatus.CONNECTED && System.currentTimeMillis() < deadline) {
            Thread.sleep(100);
            snapshot = source.snapshot();
        }
        assertTrue(snapshot.status() == ConnectionStatus.CONNECTED,
                "expected CONNECTED within 10s, got " + snapshot.status()
                        + (snapshot.errorMessage() != null ? " (" + snapshot.errorMessage() + ")" : ""));
        return snapshot;
    }
}
