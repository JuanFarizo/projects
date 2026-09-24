package com.fari.connection;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class SavedConnectionsStoreTest {

    @TempDir
    Path tempDir;

    @Test
    void loadOnMissingFileReturnsEmptyList() {
        Path path = tempDir.resolve("does-not-exist.json");

        assertTrue(SavedConnectionsStore.load(path).isEmpty());
    }

    @Test
    void loadOnCorruptFileDegradesToEmptyList() throws IOException {
        Path path = tempDir.resolve("connections.json");
        Files.writeString(path, "{ not valid json ][");

        assertTrue(SavedConnectionsStore.load(path).isEmpty());
    }

    @Test
    void saveThenLoadRoundTrips() {
        Path path = tempDir.resolve("connections.json");
        SavedConnection connection = new SavedConnection("prod-1", "10.0.0.5", 9010, "admin",
                SavedConnection.METHOD_DIRECT_REMOTE_JMX);

        SavedConnectionsStore.save(path, List.of(connection));
        List<SavedConnection> loaded = SavedConnectionsStore.load(path);

        assertEquals(List.of(connection), loaded);
    }

    @Test
    void saveNeverWritesAPassword() throws IOException {
        Path path = tempDir.resolve("connections.json");
        SavedConnection connection = new SavedConnection("prod-1", "10.0.0.5", 9010, "admin",
                SavedConnection.METHOD_DIRECT_REMOTE_JMX);

        SavedConnectionsStore.save(path, List.of(connection));
        String raw = Files.readString(path);

        assertFalse(raw.toLowerCase().contains("password"),
                "saved connections file must never contain a password field");
    }

    @Test
    void saveLeavesNoTempFileBehind() {
        Path path = tempDir.resolve("connections.json");

        SavedConnectionsStore.save(path, List.of());

        assertFalse(Files.exists(tempDir.resolve("connections.json.tmp")));
    }

    @Test
    void upsertReplacesMatchingAliasHostPort() {
        SavedConnection original = new SavedConnection("prod-1", "10.0.0.5", 9010, "",
                SavedConnection.METHOD_DIRECT_REMOTE_JMX);
        SavedConnection updated = new SavedConnection("prod-1", "10.0.0.5", 9010, "admin",
                SavedConnection.METHOD_DIRECT_REMOTE_JMX);

        List<SavedConnection> result = SavedConnectionsStore.upsert(List.of(original), updated);

        assertEquals(1, result.size());
        assertEquals(updated, result.get(0));
    }

    @Test
    void upsertAppendsWhenNoMatch() {
        SavedConnection first = new SavedConnection("prod-1", "10.0.0.5", 9010, "", SavedConnection.METHOD_DIRECT_REMOTE_JMX);
        SavedConnection second = new SavedConnection("prod-2", "10.0.0.6", 9010, "", SavedConnection.METHOD_DIRECT_REMOTE_JMX);

        List<SavedConnection> result = SavedConnectionsStore.upsert(List.of(first), second);

        assertEquals(2, result.size());
    }
}
