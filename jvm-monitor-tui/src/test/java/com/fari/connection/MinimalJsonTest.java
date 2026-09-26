package com.fari.connection;

import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class MinimalJsonTest {

    @Test
    void parsesDockerContainersJsonShape() {
        String json = """
                [
                  {
                    "Id": "abc123def456789",
                    "Names": ["/my-app"],
                    "Image": "my-app:latest",
                    "Ports": [
                      {"PrivatePort": 9010, "PublicPort": 9010, "Type": "tcp"},
                      {"PrivatePort": 9011, "PublicPort": 9011, "Type": "tcp"},
                      {"PrivatePort": 8080, "Type": "tcp"}
                    ]
                  }
                ]
                """;

        Object parsed = MinimalJson.parse(json);

        assertTrue(parsed instanceof List<?>);
        List<?> list = (List<?>) parsed;
        assertEquals(1, list.size());
        Map<?, ?> container = (Map<?, ?>) list.get(0);
        assertEquals("abc123def456789", container.get("Id"));
        assertEquals(List.of("/my-app"), container.get("Names"));
        List<?> ports = (List<?>) container.get("Ports");
        assertEquals(3, ports.size());
    }

    @Test
    void parsesPrimitives() {
        assertEquals(Boolean.TRUE, MinimalJson.parse("true"));
        assertEquals(Boolean.FALSE, MinimalJson.parse("false"));
        assertNull(MinimalJson.parse("null"));
        assertEquals(42.0, MinimalJson.parse("42"));
        assertEquals("hi", MinimalJson.parse("\"hi\""));
    }

    @Test
    void parsesEmptyObjectAndArray() {
        assertEquals(Map.of(), MinimalJson.parse("{}"));
        assertEquals(List.of(), MinimalJson.parse("[]"));
    }
}
