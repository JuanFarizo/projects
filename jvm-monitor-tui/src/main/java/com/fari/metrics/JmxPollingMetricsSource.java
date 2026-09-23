package com.fari.metrics;

import com.fari.connection.ConnectionHandle;
import com.sun.management.GarbageCollectionNotificationInfo;
import com.sun.management.OperatingSystemMXBean;
import com.sun.management.ThreadMXBean;
import com.sun.management.UnixOperatingSystemMXBean;

import javax.management.MBeanServerConnection;
import javax.management.MalformedObjectNameException;
import javax.management.Notification;
import javax.management.NotificationEmitter;
import javax.management.NotificationListener;
import javax.management.ObjectName;
import javax.management.openmbean.CompositeData;
import java.io.File;
import java.io.IOException;
import java.lang.management.BufferPoolMXBean;
import java.lang.management.ClassLoadingMXBean;
import java.lang.management.CompilationMXBean;
import java.lang.management.GarbageCollectorMXBean;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import java.lang.management.MemoryPoolMXBean;
import java.lang.management.MemoryUsage;
import java.lang.management.RuntimeMXBean;
import java.lang.management.ThreadInfo;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Deque;
import java.util.EnumMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.PriorityQueue;
import java.util.Set;
import java.util.concurrent.ConcurrentLinkedDeque;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;

/**
 * Default, always-available MetricsSource implementation
 * Runs a background poll loop and hands snapshots to the UI via a plain
 * {@code volatile} field — the render thread just reads whatever is current,
 * with no synchronization between poll cadence and render cadence, and the
 * poll loop never touches UI state directly.
 */
public final class JmxPollingMetricsSource implements MetricsSource {

    private static final int HEAP_HISTORY_SIZE = 40;
    // CPU rolling avg is labeled "60s" in the UI — one sample per poll tick.
    private static final int CPU_HISTORY_SIZE = 60;
    private static final int CLASSES_HISTORY_SIZE = 40;
    private static final int TOP_CPU_THREADS = 10;
    private static final int GC_PAUSE_HISTORY_SIZE = 40;
    // Placeholder — not derived from a measured footprint budget (requirements.md
    // admits pillars 2/3 aren't quantified yet). Revisit once there's a target.
    private static final long POLL_INTERVAL_MS = 1000;

    private volatile MetricsSnapshot latest = MetricsSnapshot.connecting();
    // Written only by the JMX notification dispatch thread (a thread the JDK
    // provides, distinct from the poll executor) — read into GcSnapshot on each
    // poll tick. Single writer per field, no lock, same contract as `latest`.
    private volatile GcPauseEvent lastGcEvent = GcPauseEvent.unavailable();
    // Same single-writer contract as lastGcEvent — only the notification
    // dispatch thread ever mutates this (addLast + its own removeFirst trim),
    // so no external synchronization is needed for the poll thread's reads.
    private final Deque<GcPauseEvent> gcPauseHistory = new ConcurrentLinkedDeque<>();

    private ConnectionHandle connection;
    private ScheduledExecutorService executor;

    private MemoryMXBean memoryBean;
    private List<MemoryPoolMXBean> memoryPools;
    private OperatingSystemMXBean osBean;
    // Proxied separately from osBean: a JDK dynamic proxy only satisfies
    // instanceof for interfaces it was actually built with, so `osBean
    // instanceof UnixOperatingSystemMXBean` is always false — null here means
    // "not Unix" (or proxy construction failed), never a live instanceof check.
    private UnixOperatingSystemMXBean unixOsBean;
    private List<GarbageCollectorMXBean> gcBeans;
    private ThreadMXBean threadBean;
    private RuntimeMXBean runtimeBean;
    private long vmStartTimeMillis;
    private ClassLoadingMXBean classLoadingBean;
    private CompilationMXBean compilationBean;
    private List<BufferPoolMXBean> bufferPools;

    // Matched out of memoryPools by name substring — same "not a stable
    // contract" risk already accepted for Eden/Old/Survivor in
    // buildHeapSnapshot() (see docs/spec/open-questions.md known risk #2).
    // Code Cache is a list, not a single bean: since JDK 9 it's segmented into
    // several "CodeHeap '...'" pools (non-nmethods/profiled/non-profiled) —
    // there's no longer a single pool named "Code Cache" to match.
    private final List<MemoryPoolMXBean> codeCacheBeans = new ArrayList<>();
    private MemoryPoolMXBean compressedClassSpaceBean;
    private MemoryPoolMXBean metaspaceBean;

    private boolean gcNotificationsSupported;
    private final NotificationListener gcNotificationListener = this::onGcNotification;

    private final Deque<Long> heapUsedHistory = new ArrayDeque<>();
    private final Deque<Long> heapCommittedHistory = new ArrayDeque<>();
    private final Deque<Long> cpuHistory = new ArrayDeque<>();
    private final Deque<Long> classesUsedHistory = new ArrayDeque<>();
    private final Deque<Long> classesCommittedHistory = new ArrayDeque<>();

    @Override
    public void start(ConnectionHandle connection) {
        this.connection = connection;
        try {
            MBeanServerConnection mbsc = connection.mbeanServerConnection();
            memoryBean = ManagementFactory.newPlatformMXBeanProxy(
                    mbsc, ManagementFactory.MEMORY_MXBEAN_NAME, MemoryMXBean.class);
            memoryPools = proxyAll(mbsc, "java.lang:type=MemoryPool,name=*", MemoryPoolMXBean.class);
            osBean = ManagementFactory.newPlatformMXBeanProxy(
                    mbsc, ManagementFactory.OPERATING_SYSTEM_MXBEAN_NAME, OperatingSystemMXBean.class);
            try {
                unixOsBean = ManagementFactory.newPlatformMXBeanProxy(
                        mbsc, ManagementFactory.OPERATING_SYSTEM_MXBEAN_NAME, UnixOperatingSystemMXBean.class);
            } catch (IOException e) {
                // Not Unix (or the underlying bean doesn't implement the extended
                // interface) — degrade, don't fail start(). fdSupported stays false.
                unixOsBean = null;
            }
            gcBeans = proxyAll(mbsc, "java.lang:type=GarbageCollector,name=*", GarbageCollectorMXBean.class);
            // queryNames()'s Set iteration order isn't a stable contract — sort by
            // name so gcAlgorithm (buildVmInfoSnapshot, index 0) is deterministic
            // instead of riding on unspecified Set ordering.
            gcBeans.sort(Comparator.comparing(GarbageCollectorMXBean::getName));
            threadBean = ManagementFactory.newPlatformMXBeanProxy(
                    mbsc, ManagementFactory.THREAD_MXBEAN_NAME, ThreadMXBean.class);
            runtimeBean = ManagementFactory.newPlatformMXBeanProxy(
                    mbsc, ManagementFactory.RUNTIME_MXBEAN_NAME, RuntimeMXBean.class);
            // Invariant for the life of the process — cache once instead of a JMX
            // round-trip on every GC notification (see onGcNotification()).
            vmStartTimeMillis = runtimeBean.getStartTime();
            classLoadingBean = ManagementFactory.newPlatformMXBeanProxy(
                    mbsc, ManagementFactory.CLASS_LOADING_MXBEAN_NAME, ClassLoadingMXBean.class);
            try {
                compilationBean = ManagementFactory.newPlatformMXBeanProxy(
                        mbsc, ManagementFactory.COMPILATION_MXBEAN_NAME, CompilationMXBean.class);
            } catch (IOException e) {
                // Not every JVM exposes a CompilationMXBean — degrade, don't fail start().
                compilationBean = null;
            }
            bufferPools = proxyAll(mbsc, "java.nio:type=BufferPool,name=*", BufferPoolMXBean.class);

            codeCacheBeans.clear();
            for (MemoryPoolMXBean pool : memoryPools) {
                String name = pool.getName();
                if (name.contains("Code Cache") || name.contains("CodeHeap")) {
                    codeCacheBeans.add(pool);
                } else if (name.contains("Compressed Class Space")) {
                    compressedClassSpaceBean = pool;
                } else if (name.contains("Metaspace")) {
                    metaspaceBean = pool;
                }
            }

            gcNotificationsSupported = connection.supportsGcNotifications();
            if (gcNotificationsSupported) {
                List<GarbageCollectorMXBean> registered = new ArrayList<>(gcBeans.size());
                try {
                    for (GarbageCollectorMXBean gcBean : gcBeans) {
                        ((NotificationEmitter) gcBean).addNotificationListener(gcNotificationListener, null, null);
                        registered.add(gcBean);
                    }
                    lastGcEvent = GcPauseEvent.pendingFirstEvent();
                } catch (Exception e) {
                    // Connection claimed JMX-notification support but the beans don't
                    // actually emit them — degrade to UNAVAILABLE rather than fail start().
                    // Unregister whichever beans succeeded before the failure so
                    // gcNotificationsSupported=false accurately reflects "no listeners
                    // registered", not just "some may still be".
                    for (GarbageCollectorMXBean gcBean : registered) {
                        try {
                            ((NotificationEmitter) gcBean).removeNotificationListener(gcNotificationListener);
                        } catch (Exception ignored) {
                            // best-effort
                        }
                    }
                    gcNotificationsSupported = false;
                    lastGcEvent = GcPauseEvent.unavailable();
                }
            } else {
                lastGcEvent = GcPauseEvent.unavailable();
            }
        } catch (IOException e) {
            latest = MetricsSnapshot.disconnected(latest.vmInfo(), "Failed to initialize metrics: " + e.getMessage());
            return;
        }

        ThreadFactory daemonPollThread = r -> {
            Thread t = new Thread(r, "jvm-monitor-poll");
            t.setDaemon(true);
            return t;
        };
        executor = Executors.newSingleThreadScheduledExecutor(daemonPollThread);
        executor.scheduleAtFixedRate(this::poll, 0, POLL_INTERVAL_MS, TimeUnit.MILLISECONDS);
    }

    private static <T> List<T> proxyAll(MBeanServerConnection mbsc, String namePattern, Class<T> type) throws IOException {
        try {
            Set<ObjectName> names = mbsc.queryNames(new ObjectName(namePattern), null);
            List<T> proxies = new ArrayList<>(names.size());
            for (ObjectName name : names) {
                proxies.add(ManagementFactory.newPlatformMXBeanProxy(mbsc, name.toString(), type));
            }
            return proxies;
        } catch (MalformedObjectNameException e) {
            throw new IOException(e);
        }
    }

    // Runs on the JDK's JMX notification dispatch thread — distinct from the
    // poll executor. Writes only this class's own `lastGcEvent` volatile field;
    // never touches `latest` or any poll-thread-owned state (heapHistory, etc).
    private void onGcNotification(Notification notification, Object handback) {
        if (!GarbageCollectionNotificationInfo.GARBAGE_COLLECTION_NOTIFICATION.equals(notification.getType())) {
            return;
        }
        GarbageCollectionNotificationInfo info =
                GarbageCollectionNotificationInfo.from((CompositeData) notification.getUserData());
        GcPauseEvent event = new GcPauseEvent(
                GcPauseAvailability.AVAILABLE,
                info.getGcName(),
                info.getGcCause(),
                isFullGc(info.getGcName(), info.getGcAction()),
                info.getGcInfo().getDuration(),
                info.getGcInfo().getEndTime() + vmStartTimeMillis
        );
        lastGcEvent = event;
        gcPauseHistory.addLast(event);
        while (gcPauseHistory.size() > GC_PAUSE_HISTORY_SIZE) {
            gcPauseHistory.removeFirst();
        }
    }

    // Young-vs-full split by name/action substring match — same risk class as
    // the Eden/Old/Survivor pool-name matching (open-questions.md known risk #2).
    private static boolean isFullGc(String gcName, String gcAction) {
        if (gcAction != null && gcAction.toLowerCase(Locale.ROOT).contains("major")) {
            return true;
        }
        return gcName != null && (gcName.contains("Old") || gcName.contains("MarkSweep") || gcName.contains("Full"));
    }

    private void poll() {
        try {
            latest = buildSnapshot();
        } catch (Exception e) {
            // Target died, connection dropped, or a transient JMX failure — degrade
            // to a clear DISCONNECTED status and stop polling. Never crash the loop
            // or leave it retrying forever.
            latest = MetricsSnapshot.disconnected(latest.vmInfo(), e.getMessage());
            if (executor != null) {
                executor.shutdown();
            }
        }
    }

    private MetricsSnapshot buildSnapshot() throws IOException {
        HeapSnapshot heap = buildHeapSnapshot();
        NonHeapSnapshot nonHeap = buildNonHeapSnapshot();
        BuffersSnapshot buffers = buildBuffersSnapshot();
        CpuSnapshot cpu = buildCpuSnapshot();
        GcSnapshot gc = buildGcSnapshot();
        ThreadSnapshot threads = buildThreadSnapshot();
        ClassesSnapshot classes = buildClassesSnapshot();
        VmInfoSnapshot vmInfo = buildVmInfoSnapshot(gc);
        return new MetricsSnapshot(ConnectionStatus.CONNECTED, vmInfo, heap, nonHeap, buffers, cpu, gc, threads,
                classes, null);
    }

    private HeapSnapshot buildHeapSnapshot() throws IOException {
        MemoryUsage heapUsage = memoryBean.getHeapMemoryUsage();

        long eden = 0;
        long old = 0;
        long survivor = 0;
        for (MemoryPoolMXBean pool : memoryPools) {
            String name = pool.getName();
            MemoryUsage usage = pool.getUsage();
            if (usage == null) {
                continue;
            }
            if (name.contains("Eden")) {
                eden = usage.getUsed();
            } else if (name.contains("Old") || name.contains("Tenured")) {
                old = usage.getUsed();
            } else if (name.contains("Survivor")) {
                survivor = usage.getUsed();
            }
        }

        // MB, not raw bytes: raw byte counts blow past the sparkline y-axis
        // label's 4-digit cap ("999+"), and MB is what's already shown elsewhere.
        pushBounded(heapUsedHistory, heapUsage.getUsed() / (1024 * 1024), HEAP_HISTORY_SIZE);
        pushBounded(heapCommittedHistory, heapUsage.getCommitted() / (1024 * 1024), HEAP_HISTORY_SIZE);
        return new HeapSnapshot(heapUsage.getUsed(), heapUsage.getCommitted(), heapUsage.getMax(),
                eden, old, survivor, toArray(heapUsedHistory), toArray(heapCommittedHistory));
    }

    private NonHeapSnapshot buildNonHeapSnapshot() throws IOException {
        MemoryUsage nonHeapUsage = memoryBean.getNonHeapMemoryUsage();
        long codeCacheUsed = 0;
        for (MemoryPoolMXBean pool : codeCacheBeans) {
            codeCacheUsed += poolUsed(pool);
        }
        long compressedClassSpaceUsed = poolUsed(compressedClassSpaceBean);
        return new NonHeapSnapshot(nonHeapUsage.getUsed(), nonHeapUsage.getCommitted(), nonHeapUsage.getMax(),
                codeCacheUsed, compressedClassSpaceUsed);
    }

    private static long poolUsed(MemoryPoolMXBean pool) throws IOException {
        if (pool == null) {
            return 0;
        }
        MemoryUsage usage = pool.getUsage();
        return usage == null ? 0 : usage.getUsed();
    }

    private BuffersSnapshot buildBuffersSnapshot() throws IOException {
        BufferPoolSnapshot direct = BufferPoolSnapshot.empty();
        BufferPoolSnapshot mapped = BufferPoolSnapshot.empty();
        for (BufferPoolMXBean pool : bufferPools) {
            String name = pool.getName();
            BufferPoolSnapshot snapshot =
                    new BufferPoolSnapshot(pool.getCount(), pool.getMemoryUsed(), pool.getTotalCapacity());
            if ("direct".equals(name)) {
                direct = snapshot;
            } else if ("mapped".equals(name)) {
                mapped = snapshot;
            }
        }
        return new BuffersSnapshot(direct, mapped);
    }

    private CpuSnapshot buildCpuSnapshot() throws IOException {
        double processLoad = osBean.getProcessCpuLoad();
        double systemLoad = osBean.getCpuLoad();
        int cores = osBean.getAvailableProcessors();

        // Tenths of a percent, not whole percent: rounding to whole percent
        // quantizes any load under ~1.5% to the same 0/1 value, flattening the
        // sparkline and skewing the rolling avg whenever load sits in that range.
        long cpuTenths = Math.round(Math.max(processLoad, 0) * 1000);
        pushBounded(cpuHistory, cpuTenths, CPU_HISTORY_SIZE);
        double rollingAvg = cpuHistory.stream().mapToLong(Long::longValue).average().orElse(0) / 10.0;

        return new CpuSnapshot(processLoad, systemLoad, cores, rollingAvg, toArray(cpuHistory));
    }

    private GcSnapshot buildGcSnapshot() throws IOException {
        List<GcCollectorStat> collectors = new ArrayList<>(gcBeans.size());
        for (GarbageCollectorMXBean gcBean : gcBeans) {
            long count = gcBean.getCollectionCount();
            long time = gcBean.getCollectionTime();
            double avgPause = count > 0 ? (double) time / count : 0;
            collectors.add(new GcCollectorStat(gcBean.getName(), count, time, avgPause));
        }
        return new GcSnapshot(collectors, lastGcEvent, List.copyOf(gcPauseHistory));
    }

    private ThreadSnapshot buildThreadSnapshot() throws IOException {
        // Priciest call in the poll loop (snapshots every thread's info) — first
        // place to optimize (e.g. slower cadence for the state breakdown) if
        // profiling shows this adds noticeable load to the target JVM.
        long[] threadIds = threadBean.getAllThreadIds();
        ThreadInfo[] infos = threadBean.getThreadInfo(threadIds);
        Map<Thread.State, Integer> stateCounts = new EnumMap<>(Thread.State.class);
        for (ThreadInfo info : infos) {
            if (info == null) {
                continue;
            }
            stateCounts.merge(info.getThreadState(), 1, Integer::sum);
        }

        // Same threadIds array the state breakdown just enumerated — no second
        // getAllThreadIds() call.
        long[] cpuTimes = threadBean.getThreadCpuTime(threadIds);
        List<ThreadCpuStat> topCpuThreads = topNByCpu(threadIds, infos, cpuTimes, TOP_CPU_THREADS);

        // Covers both monitor and ownable-synchronizer deadlocks, so
        // findMonitorDeadlockedThreads() isn't additionally called. Fast/cheap
        // when there's no deadlock cycle — no throttling needed at this cadence.
        long[] deadlocked = threadBean.findDeadlockedThreads();
        if (deadlocked == null) {
            deadlocked = new long[0];
        }
        List<DeadlockedThread> deadlockedThreads = deadlocked.length == 0
                ? List.of()
                : buildDeadlockedThreads(deadlocked);

        return new ThreadSnapshot(threadBean.getThreadCount(), threadBean.getDaemonThreadCount(),
                threadBean.getPeakThreadCount(), threadBean.getTotalStartedThreadCount(), stateCounts,
                deadlockedThreads, topCpuThreads);
    }

    // Only called when a deadlock cycle actually exists — one extra
    // getThreadInfo() round-trip paid solely during a real deadlock, not
    // every poll tick. Lock class name + owner name come off the same
    // ThreadInfo, no setThreadContentionMonitoringEnabled() needed (that flag
    // is only for blocked/waited counts+time — the separate, rejected
    // "lock contention" feature in docs/spec/metrics.md).
    private List<DeadlockedThread> buildDeadlockedThreads(long[] deadlockedIds) throws IOException {
        ThreadInfo[] infos = threadBean.getThreadInfo(deadlockedIds);
        List<DeadlockedThread> threads = new ArrayList<>(infos.length);
        for (ThreadInfo info : infos) {
            if (info == null) {
                continue;
            }
            String lockClassName = info.getLockInfo() != null ? info.getLockInfo().getClassName() : null;
            threads.add(new DeadlockedThread(info.getThreadId(), info.getThreadName(), lockClassName,
                    info.getLockOwnerName()));
        }
        return List.copyOf(threads);
    }

    // Bounded min-heap of capacity n instead of collect-all-then-sort: O(threadCount
    // log n) instead of O(threadCount log threadCount), and never materializes more
    // than n ThreadCpuStat records regardless of live thread count.
    private static List<ThreadCpuStat> topNByCpu(long[] threadIds, ThreadInfo[] infos, long[] cpuTimes, int n) {
        PriorityQueue<ThreadCpuStat> heap = new PriorityQueue<>(n, Comparator.comparingLong(ThreadCpuStat::cpuTimeNanos));
        for (int i = 0; i < threadIds.length; i++) {
            // Negative cpu time: thread exited between enumeration and the cpu-time
            // call, or per-thread CPU time measurement isn't supported.
            if (infos[i] == null || cpuTimes[i] < 0) {
                continue;
            }
            ThreadCpuStat stat = new ThreadCpuStat(threadIds[i], infos[i].getThreadName(),
                    infos[i].getThreadState(), cpuTimes[i]);
            if (heap.size() < n) {
                heap.add(stat);
            } else if (heap.peek().cpuTimeNanos() < stat.cpuTimeNanos()) {
                heap.poll();
                heap.add(stat);
            }
        }
        List<ThreadCpuStat> topN = new ArrayList<>(heap);
        topN.sort(Comparator.comparingLong(ThreadCpuStat::cpuTimeNanos).reversed());
        return List.copyOf(topN);
    }

    private ClassesSnapshot buildClassesSnapshot() throws IOException {
        long used = 0;
        long committed = 0;
        if (metaspaceBean != null) {
            MemoryUsage usage = metaspaceBean.getUsage();
            if (usage != null) {
                used = usage.getUsed();
                committed = usage.getCommitted();
            }
        }
        long loaded = classLoadingBean.getLoadedClassCount();
        long unloaded = classLoadingBean.getUnloadedClassCount();

        pushBounded(classesUsedHistory, used / (1024 * 1024), CLASSES_HISTORY_SIZE);
        pushBounded(classesCommittedHistory, committed / (1024 * 1024), CLASSES_HISTORY_SIZE);
        return new ClassesSnapshot(used, committed, loaded, unloaded,
                toArray(classesUsedHistory), toArray(classesCommittedHistory));
    }

    private VmInfoSnapshot buildVmInfoSnapshot(GcSnapshot gc) throws IOException {
        String gcAlgorithm = gc.collectors().isEmpty() ? "unknown"
                : gc.collectors().get(0).name().replace(" Young Generation", "").replace(" Old Generation", "");

        long jitCompilationTimeMs = compilationBean != null && compilationBean.isCompilationTimeMonitoringSupported()
                ? compilationBean.getTotalCompilationTime() : 0;

        // Unix-only — same risk class as open-questions.md known risk #1
        // (getCpuLoad()-style JDK-version guard): guarded by whether the
        // separate unixOsBean proxy (see field comment) was constructed,
        // blank elsewhere rather than throwing.
        boolean fdSupported = unixOsBean != null;
        long fdOpen = 0;
        long fdMax = 0;
        if (fdSupported) {
            fdOpen = unixOsBean.getOpenFileDescriptorCount();
            fdMax = unixOsBean.getMaxFileDescriptorCount();
        }

        return new VmInfoSnapshot(
                connection.label(),
                runtimeBean.getVmName() + " " + runtimeBean.getVmVersion(),
                gcAlgorithm,
                runtimeBean.getInputArguments().size(),
                classpathEntryCount(runtimeBean),
                runtimeBean.getUptime(),
                jitCompilationTimeMs,
                osBean.getSystemLoadAverage(),
                osBean.getTotalMemorySize(),
                osBean.getFreeMemorySize(),
                osBean.getTotalSwapSpaceSize(),
                osBean.getFreeSwapSpaceSize(),
                fdOpen,
                fdMax,
                fdSupported
        );
    }

    private static int classpathEntryCount(RuntimeMXBean bean) throws IOException {
        String classPath = bean.getClassPath();
        if (classPath == null || classPath.isBlank()) {
            return 0;
        }
        return classPath.split(File.pathSeparator).length;
    }

    private static void pushBounded(Deque<Long> history, long value, int maxSize) {
        history.addLast(value);
        if (history.size() > maxSize) {
            history.removeFirst();
        }
    }

    private static long[] toArray(Deque<Long> history) {
        long[] array = new long[history.size()];
        int i = 0;
        for (long value : history) {
            array[i++] = value;
        }
        return array;
    }

    @Override
    public MetricsSnapshot snapshot() {
        return latest;
    }

    @Override
    public void close() {
        if (gcBeans != null && gcNotificationsSupported) {
            for (GarbageCollectorMXBean gcBean : gcBeans) {
                try {
                    ((NotificationEmitter) gcBean).removeNotificationListener(gcNotificationListener);
                } catch (Exception ignored) {
                    // best-effort — target may already be gone
                }
            }
        }
        if (executor != null) {
            executor.shutdownNow();
        }
        if (connection != null) {
            connection.close();
        }
    }
}
