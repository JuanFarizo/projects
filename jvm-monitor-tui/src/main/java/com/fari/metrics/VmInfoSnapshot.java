package com.fari.metrics;

public record VmInfoSnapshot(
        String label,
        String jvmVersion,
        String gcAlgorithm,
        int vmArgCount,
        int classpathEntryCount,
        long uptimeMillis
) {
    public static VmInfoSnapshot empty() {
        return new VmInfoSnapshot("", "", "", 0, 0, 0);
    }
}
