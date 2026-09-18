package com.fari.connection;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertTrue;

class ProcessDiscoveryTest {

    @Test
    void listLocalJvmsIncludesTheCurrentProcess() {
        String currentPid = String.valueOf(ProcessHandle.current().pid());

        List<LocalProcessInfo> processes = ProcessDiscovery.listLocalJvms();

        assertTrue(processes.stream().anyMatch(p -> p.pid().equals(currentPid)),
                "expected current JVM's own PID (" + currentPid + ") to appear in local process listing");
    }
}
