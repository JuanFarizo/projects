package com.fari;

import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import java.util.List;
import java.util.Scanner;

import javax.management.MBeanServerConnection;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;

import com.sun.tools.attach.VirtualMachine;
import com.sun.tools.attach.VirtualMachineDescriptor;

public class App {
    public static void main(String[] args) throws Exception {
        // Discovery service, scans for JVMs
        List<VirtualMachineDescriptor> vmDescriptors = VirtualMachine.list();
        for (int i = 0; i < vmDescriptors.size(); i++) {
            IO.println(i + " ID: " + vmDescriptors.get(i).id() + " --> " + vmDescriptors.get(i).displayName());
        }

        Scanner scanner = new Scanner(System.in);
        IO.println("Select JVM index to attach:");
        int index = Integer.parseInt(scanner.nextLine().trim());

        VirtualMachineDescriptor selected = vmDescriptors.get(index);
        VirtualMachine vm = VirtualMachine.attach(selected);
        IO.println("Attached: " + selected.id() + " " + selected.displayName());
        // Connection manager - opens JMX connector
        String connectionAddress = vm.startLocalManagementAgent();
        JMXServiceURL url = new JMXServiceURL(connectionAddress);
        JMXConnector connector = JMXConnectorFactory.connect(url);
        MBeanServerConnection mbsc = connector.getMBeanServerConnection();
        MemoryMXBean mem = ManagementFactory.newPlatformMXBeanProxy(mbsc, ManagementFactory.MEMORY_MXBEAN_NAME, MemoryMXBean.class);
        IO.println(" Heap used memory " + mem.getHeapMemoryUsage().getUsed() + " bytes");
        connector.close();
        scanner.close();
        vm.detach();
    }
}
