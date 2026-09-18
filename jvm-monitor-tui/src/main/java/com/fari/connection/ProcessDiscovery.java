package com.fari.connection;

import com.sun.tools.attach.VirtualMachine;
import com.sun.tools.attach.VirtualMachineDescriptor;

import java.nio.file.Paths;
import java.util.List;

/** jps-equivalent listing: enumerates local JVMs without attaching to any of them. */
public final class ProcessDiscovery {

    private ProcessDiscovery() {
    }

    public static List<LocalProcessInfo> listLocalJvms() {
        return VirtualMachine.list().stream()
                .map(vm -> createLocalProcessInfoFromDesriptor(vm))
                .toList();
    }

    private static LocalProcessInfo createLocalProcessInfoFromDesriptor(VirtualMachineDescriptor vmd) {
        String displayName = vmd.displayName();
        String name;
        if (displayName == null || displayName.isBlank()) {
            name = "Unknown";
        }
        String[] split = displayName.split("\\s+", 2);
        String entryPoint = split[0];
        String args = (split.length > 1) ? split[1] : "";
        if (entryPoint.contains("/") || entryPoint.contains("\\")) {
            name = Paths.get(entryPoint).getFileName().toString();
        } else if (entryPoint.contains(".")) {
            name = entryPoint.substring(entryPoint.lastIndexOf(".") + 1);
        } else {
            name = entryPoint;
        }
        return new LocalProcessInfo(vmd.id(), name, args);
    }
}
