package com.fari.metrics;

public record MetricsSnapshot(
        ConnectionStatus status,
        VmInfoSnapshot vmInfo,
        HeapSnapshot heap,
        NonHeapSnapshot nonHeap,
        BuffersSnapshot buffers,
        CpuSnapshot cpu,
        GcSnapshot gc,
        ThreadSnapshot threads,
        ClassesSnapshot classes,
        String errorMessage
) {
    public static MetricsSnapshot connecting() {
        return new MetricsSnapshot(ConnectionStatus.CONNECTING, VmInfoSnapshot.empty(),
                HeapSnapshot.empty(), NonHeapSnapshot.empty(), BuffersSnapshot.empty(), CpuSnapshot.empty(),
                GcSnapshot.empty(), ThreadSnapshot.empty(), ClassesSnapshot.empty(), null);
    }

    public static MetricsSnapshot disconnected(VmInfoSnapshot lastKnownVmInfo, String errorMessage) {
        return new MetricsSnapshot(ConnectionStatus.DISCONNECTED, lastKnownVmInfo,
                HeapSnapshot.empty(), NonHeapSnapshot.empty(), BuffersSnapshot.empty(), CpuSnapshot.empty(),
                GcSnapshot.empty(), ThreadSnapshot.empty(), ClassesSnapshot.empty(), errorMessage);
    }
}
