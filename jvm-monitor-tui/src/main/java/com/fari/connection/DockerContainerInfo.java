package com.fari.connection;

import java.util.Collections;
import java.util.List;

/**
 * A running container with 2+ published TCP ports, the shape that lets a plain
 * {@link RemoteJmxConnection} reach it, no tunnel needed.
 */
public record DockerContainerInfo(String id, String name, String image, List<Integer> publishedTcpPorts) {

    /**
     * Every documented Docker-JMX setup publishes the RMI registry port lower than
     * the RMI object port (e.g. 9010/9011) — connecting to the wrong one fails the RMI
     * lookup outright, so a wrong guess here is a loud connect error, not silently-wrong metrics.
     */
    public int registryPort() {
        return Collections.min(publishedTcpPorts);
    }
}
