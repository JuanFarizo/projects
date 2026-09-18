package com.fari.metrics;

import com.fari.connection.ConnectionHandle;
import com.sun.management.OperatingSystemMXBean;

import javax.management.MBeanServerConnection;
import javax.management.MalformedObjectNameException;
import javax.management.ObjectName;
import java.io.File;
import java.io.IOException;
import java.lang.management.GarbageCollectorMXBean;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import java.lang.management.MemoryPoolMXBean;
import java.lang.management.MemoryUsage;
import java.lang.management.RuntimeMXBean;
import java.lang.management.ThreadInfo;
import java.lang.management.ThreadMXBean;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;

/**
 * Default, always-available MetricsSource implementation (per architecture.md).
 * Runs a background poll loop and hands snapshots to the UI via a plain
 * {@code volatile} field — the render thread just reads whatever is current,
 * with no synchronization between poll cadence and render cadence, and the
 * poll loop never touches UI state directly.
 */
public final class JmxPollingMetricsSource implements MetricsSource {

    private static final int HEAP_HISTORY_SIZE = 40;
    // CPU rolling avg is labeled "60s" in the UI — one sample per poll tick.
    private static final int CPU_HISTORY_SIZE = 60;
    // Placeholder — not derived from a measured footprint budget (requirements.md
    // admits pillars 2/3 aren't quantified yet). Revisit once there's a target.
    private static final long POLL_INTERVAL_MS = 1000;

    private volatile MetricsSnapshot latest = MetricsSnapshot.connecting();

    private ConnectionHandle connection;
    private ScheduledExecutorService executor;

    private MemoryMXBean memoryBean;
    private List<MemoryPoolMXBean> memoryPools;
    private OperatingSystemMXBean osBean;
    private List<GarbageCollectorMXBean> gcBeans;
    private ThreadMXBean threadBean;
    private RuntimeMXBean runtimeBean;

    private final Deque<Long> heapHistory = new ArrayDeque<>();
    private final Deque<Long> cpuHistory = new ArrayDeque<>();

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
            gcBeans = proxyAll(mbsc, "java.lang:type=GarbageCollector,name=*", GarbageCollectorMXBean.class);
            threadBean = ManagementFactory.newPlatformMXBeanProxy(
                    mbsc, ManagementFactory.THREAD_MXBEAN_NAME, ThreadMXBean.class);
            runtimeBean = ManagementFactory.newPlatformMXBeanProxy(
                    mbsc, ManagementFactory.RUNTIME_MXBEAN_NAME, RuntimeMXBean.class);
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
        CpuSnapshot cpu = buildCpuSnapshot();
        GcSnapshot gc = buildGcSnapshot();
        ThreadSnapshot threads = buildThreadSnapshot();
        VmInfoSnapshot vmInfo = buildVmInfoSnapshot(gc);
        return new MetricsSnapshot(ConnectionStatus.CONNECTED, vmInfo, heap, cpu, gc, threads, null);
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
        pushBounded(heapHistory, heapUsage.getUsed() / (1024 * 1024), HEAP_HISTORY_SIZE);
        return new HeapSnapshot(heapUsage.getUsed(), heapUsage.getCommitted(), heapUsage.getMax(),
                eden, old, survivor, toArray(heapHistory));
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
        return new GcSnapshot(collectors);
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
        return new ThreadSnapshot(threadBean.getThreadCount(), threadBean.getDaemonThreadCount(),
                threadBean.getPeakThreadCount(), threadBean.getTotalStartedThreadCount(), stateCounts);
    }

    private VmInfoSnapshot buildVmInfoSnapshot(GcSnapshot gc) throws IOException {
        String gcAlgorithm = gc.collectors().isEmpty() ? "unknown"
                : gc.collectors().get(0).name().replace(" Young Generation", "").replace(" Old Generation", "");
        return new VmInfoSnapshot(
                connection.label(),
                runtimeBean.getVmName() + " " + runtimeBean.getVmVersion(),
                gcAlgorithm,
                runtimeBean.getInputArguments().size(),
                classpathEntryCount(runtimeBean),
                runtimeBean.getUptime()
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
        if (executor != null) {
            executor.shutdownNow();
        }
        if (connection != null) {
            connection.close();
        }
    }
}
