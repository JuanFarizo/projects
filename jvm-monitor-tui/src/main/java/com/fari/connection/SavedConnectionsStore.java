package com.fari.connection;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Reads/writes the saved-connection profiles JSON file described in
 * docs/specs/architecture.md's "Saved-connection persistence" section.
 * <p>
 * No JSON library dependency — the file is a flat array of flat objects with
 * five known fields, narrow enough that a hand-rolled reader/writer is
 * lighter than pulling in Jackson/Gson for it (pillar 2).
 */
public final class SavedConnectionsStore {

    private SavedConnectionsStore() {
    }

    public static Path defaultPath() {// TODO: This is only for Mac/Linux? Check how to support Windows
        return Path.of(System.getProperty("user.home"), ".config", "jvm-monitor-tui", "connections.json");
    }

    /** Missing file or any parse failure degrades to an empty list rather than throwing. */
    public static List<SavedConnection> load(Path path) {
        try {
            if (!Files.exists(path)) {
                return List.of();
            }
            String text = Files.readString(path, StandardCharsets.UTF_8);
            return Json.parseConnections(text);
        } catch (IOException | RuntimeException e) {
            return List.of();
        }
    }

    /** Atomic write: write to a temp file in the same directory, then rename over the target. */
    public static void save(Path path, List<SavedConnection> connections) {
        try {
            Path parent = path.getParent();
            if (parent != null) {
                Files.createDirectories(parent);
            }
            Path tmp = parent != null ? parent.resolve(path.getFileName() + ".tmp") : Path.of(path + ".tmp");
            Files.writeString(tmp, Json.writeConnections(connections), StandardCharsets.UTF_8);
            Files.move(tmp, path, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
        } catch (IOException e) {
            throw new ConnectionException("Failed to save connections to " + path, e);
        }
    }

    /** Dedupe key is (alias, host, port) — replaces the matching entry in place, else appends. */
    public static List<SavedConnection> upsert(List<SavedConnection> existing, SavedConnection toSave) {
        List<SavedConnection> result = new ArrayList<>(existing);
        for (int i = 0; i < result.size(); i++) {
            SavedConnection c = result.get(i);
            if (c.alias().equals(toSave.alias()) && c.host().equals(toSave.host()) && c.port() == toSave.port()) {
                result.set(i, toSave);
                return result;
            }
        }
        result.add(toSave);
        return result;
    }

    /** Replaces the entry matching updated's id — the edit path, identity-keyed rather than dedupe-keyed. */
    public static List<SavedConnection> update(List<SavedConnection> existing, SavedConnection updated) {
        List<SavedConnection> result = new ArrayList<>(existing);
        for (int i = 0; i < result.size(); i++) {
            if (result.get(i).id().equals(updated.id())) {
                result.set(i, updated);
                return result;
            }
        }
        result.add(updated);
        return result;
    }

    public static List<SavedConnection> delete(List<SavedConnection> existing, String id) {
        List<SavedConnection> result = new ArrayList<>(existing);
        result.removeIf(c -> c.id().equals(id));
        return result;
    }

    /** Minimal hand-rolled JSON — scoped to this one array-of-flat-objects shape only. */
    private static final class Json {

        static String writeConnections(List<SavedConnection> connections) {
            StringBuilder sb = new StringBuilder("[\n");
            for (int i = 0; i < connections.size(); i++) {
                SavedConnection c = connections.get(i);
                sb.append("  {");
                sb.append("\"id\":").append(quote(c.id())).append(',');
                sb.append("\"alias\":").append(quote(c.alias())).append(',');
                sb.append("\"host\":").append(quote(c.host())).append(',');
                sb.append("\"port\":").append(c.port()).append(',');
                sb.append("\"username\":").append(quote(c.username())).append(',');
                sb.append("\"method\":").append(quote(c.method()));
                sb.append('}');
                if (i < connections.size() - 1) {
                    sb.append(',');
                }
                sb.append('\n');
            }
            sb.append(']');
            return sb.toString();
        }

        static String quote(String s) {
            StringBuilder sb = new StringBuilder("\"");
            for (int i = 0; i < s.length(); i++) {
                char c = s.charAt(i);
                switch (c) {
                    case '"' -> sb.append("\\\"");
                    case '\\' -> sb.append("\\\\");
                    case '\n' -> sb.append("\\n");
                    case '\r' -> sb.append("\\r");
                    case '\t' -> sb.append("\\t");
                    default -> {
                        if (c < 0x20) {
                            sb.append(String.format("\\u%04x", (int) c));
                        } else {
                            sb.append(c);
                        }
                    }
                }
            }
            return sb.append('"').toString();
        }

        static List<SavedConnection> parseConnections(String text) {
            Scanner scanner = new Scanner(text);
            scanner.skipWs();
            List<SavedConnection> result = new ArrayList<>();
            scanner.expect('[');
            scanner.skipWs();
            if (scanner.peek() == ']') {
                scanner.pos++;
                return result;
            }
            while (true) {
                Map<String, Object> obj = scanner.parseObject();
                result.add(toConnection(obj));
                scanner.skipWs();
                char c = scanner.peek();
                if (c == ',') {
                    scanner.pos++;
                    scanner.skipWs();
                } else {
                    break;
                }
            }
            scanner.skipWs();
            scanner.expect(']');
            return result;
        }

        private static SavedConnection toConnection(Map<String, Object> obj) {
            // Entries written before the id field existed get one generated here;
            // it's persisted back on the next save() (no separate migration step).
            String id = (String) obj.get("id");
            if (id == null || id.isBlank()) {
                id = UUID.randomUUID().toString();
            }
            String alias = (String) obj.getOrDefault("alias", "");
            String host = (String) obj.getOrDefault("host", "");
            int port = ((Number) obj.getOrDefault("port", 0)).intValue();
            String username = (String) obj.getOrDefault("username", "");
            String method = (String) obj.getOrDefault("method", SavedConnection.METHOD_DIRECT_REMOTE_JMX);
            return new SavedConnection(id, alias, host, port, username, method);
        }

        private static final class Scanner {
            final String s;
            int pos;

            Scanner(String s) {
                this.s = s;
                this.pos = 0;
            }

            char peek() {
                return pos < s.length() ? s.charAt(pos) : '\0';
            }

            void skipWs() {
                while (pos < s.length() && Character.isWhitespace(s.charAt(pos))) {
                    pos++;
                }
            }

            void expect(char c) {
                if (peek() != c) {
                    throw new IllegalStateException("Expected '" + c + "' at position " + pos);
                }
                pos++;
            }

            Map<String, Object> parseObject() {
                skipWs();
                Map<String, Object> map = new LinkedHashMap<>();
                expect('{');
                skipWs();
                if (peek() == '}') {
                    pos++;
                    return map;
                }
                while (true) {
                    skipWs();
                    String key = parseString();
                    skipWs();
                    expect(':');
                    skipWs();
                    Object value = parseValue();
                    map.put(key, value);
                    skipWs();
                    char c = peek();
                    if (c == ',') {
                        pos++;
                    } else {
                        break;
                    }
                }
                skipWs();
                expect('}');
                return map;
            }

            Object parseValue() {
                char c = peek();
                if (c == '"') {
                    return parseString();
                }
                if (c == '-' || Character.isDigit(c)) {
                    return parseNumber();
                }
                throw new IllegalStateException("Unexpected value at position " + pos);
            }

            String parseString() {
                expect('"');
                StringBuilder sb = new StringBuilder();
                while (true) {
                    if (pos >= s.length()) {
                        throw new IllegalStateException("Unterminated string");
                    }
                    char c = s.charAt(pos++);
                    if (c == '"') {
                        break;
                    }
                    if (c == '\\') {
                        char esc = s.charAt(pos++);
                        switch (esc) {
                            case '"' -> sb.append('"');
                            case '\\' -> sb.append('\\');
                            case '/' -> sb.append('/');
                            case 'n' -> sb.append('\n');
                            case 'r' -> sb.append('\r');
                            case 't' -> sb.append('\t');
                            case 'b' -> sb.append('\b');
                            case 'f' -> sb.append('\f');
                            case 'u' -> {
                                String hex = s.substring(pos, pos + 4);
                                sb.append((char) Integer.parseInt(hex, 16));
                                pos += 4;
                            }
                            default -> throw new IllegalStateException("Invalid escape at position " + pos);
                        }
                    } else {
                        sb.append(c);
                    }
                }
                return sb.toString();
            }

            Integer parseNumber() {
                int start = pos;
                if (peek() == '-') {
                    pos++;
                }
                while (pos < s.length() && Character.isDigit(s.charAt(pos))) {
                    pos++;
                }
                return Integer.parseInt(s.substring(start, pos));
            }
        }
    }
}
