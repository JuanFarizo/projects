package com.fari;

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
        List<VirtualMachineDescriptor> vms = VirtualMachine.list();
        for (int i = 0; i < vms.size(); i++) {
            IO.println(i + " " + vms.get(i).id() + " --> " + vms.get(i).displayName());
        }

        Scanner scanner = new Scanner(System.in);
        IO.println("Select JVM index to attach:");
        int index = Integer.parseInt(scanner.nextLine().trim());

        VirtualMachineDescriptor selected = vms.get(index);
        VirtualMachine vm = VirtualMachine.attach(selected);
        IO.println("Attached: " + selected.id() + " " + selected.displayName());
        String connectionAddress = vm.startLocalManagementAgent();
        vm.detach();
        JMXServiceURL url = new JMXServiceURL(connectionAddress);
        JMXConnector connector = JMXConnectorFactory.connect(url);
        MBeanServerConnection mbsc = connector.getMBeanServerConnection();
    }
}
