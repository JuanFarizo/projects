package com.fari.metrics;

public record VmInfoSnapshot(
        String label,
        String jvmVersion,
        String gcAlgorithm,
        int vmArgCount,
        int classpathEntryCount,
        long uptimeMillis,
        long jitCompilationTimeMs,
        double systemLoadAverage,
        long physicalMemoryTotal,
        long physicalMemoryFree,
        long swapTotal,
        long swapFree,
        long openFileDescriptorCount,
        long maxFileDescriptorCount,
        boolean fileDescriptorsSupported
) {
    public static VmInfoSnapshot empty() {
        return new VmInfoSnapshot("", "", "", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false);
    }
}
