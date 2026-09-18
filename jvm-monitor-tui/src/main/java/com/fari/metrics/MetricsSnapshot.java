package com.fari.metrics;

public record MetricsSnapshot(
        ConnectionStatus status,
        VmInfoSnapshot vmInfo,
        HeapSnapshot heap,
        CpuSnapshot cpu,
        GcSnapshot gc,
        ThreadSnapshot threads,
        String errorMessage
) {
    public static MetricsSnapshot connecting() {
        return new MetricsSnapshot(ConnectionStatus.CONNECTING, VmInfoSnapshot.empty(),
                HeapSnapshot.empty(), CpuSnapshot.empty(), GcSnapshot.empty(), ThreadSnapshot.empty(), null);
    }

    public static MetricsSnapshot disconnected(VmInfoSnapshot lastKnownVmInfo, String errorMessage) {
        return new MetricsSnapshot(ConnectionStatus.DISCONNECTED, lastKnownVmInfo,
                HeapSnapshot.empty(), CpuSnapshot.empty(), GcSnapshot.empty(), ThreadSnapshot.empty(), errorMessage);
    }
}
