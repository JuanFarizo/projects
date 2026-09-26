package com.fari.connection;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;

class DockerContainerInfoTest {

    @Test
    void registryPortIsTheLowestPublishedPort() {
        var container = new DockerContainerInfo("abc123", "my-app", "my-app:latest", List.of(9011, 9010));

        assertEquals(9010, container.registryPort());
    }
}
