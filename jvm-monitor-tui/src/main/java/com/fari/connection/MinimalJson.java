package com.fari.connection;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Small generic JSON reader (object/array/string/number/boolean/null), used only by
 * {@link DockerDiscovery} to read the Docker Engine API's {@code /containers/json} response —
 * arrays of objects with nested arrays, a shape {@link SavedConnectionsStore}'s own hand-rolled
 * parser (flat objects, no arrays) doesn't cover. Kept separate rather than extending that one,
 * since the two parse unrelated response shapes for unrelated stores.
 */
final class MinimalJson {

    private MinimalJson() {
    }

    static Object parse(String text) {
        Parser p = new Parser(text);
        p.skipWs();
        Object value = p.parseValue();
        p.skipWs();
        return value;
    }

    private static final class Parser {
        final String s;
        int pos;

        Parser(String s) {
            this.s = s;
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

        Object parseValue() {
            skipWs();
            char c = peek();
            return switch (c) {
                case '{' -> parseObject();
                case '[' -> parseArray();
                case '"' -> parseString();
                case 't' -> parseLiteral("true", Boolean.TRUE);
                case 'f' -> parseLiteral("false", Boolean.FALSE);
                case 'n' -> parseLiteral("null", null);
                default -> parseNumber();
            };
        }

        Map<String, Object> parseObject() {
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

        List<Object> parseArray() {
            List<Object> list = new ArrayList<>();
            expect('[');
            skipWs();
            if (peek() == ']') {
                pos++;
                return list;
            }
            while (true) {
                list.add(parseValue());
                skipWs();
                char c = peek();
                if (c == ',') {
                    pos++;
                } else {
                    break;
                }
            }
            skipWs();
            expect(']');
            return list;
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

        Double parseNumber() {
            int start = pos;
            if (peek() == '-') {
                pos++;
            }
            while (pos < s.length() && (Character.isDigit(s.charAt(pos)) || s.charAt(pos) == '.'
                    || s.charAt(pos) == 'e' || s.charAt(pos) == 'E' || s.charAt(pos) == '+' || s.charAt(pos) == '-')) {
                pos++;
            }
            return Double.parseDouble(s.substring(start, pos));
        }

        Object parseLiteral(String literal, Object value) {
            if (!s.regionMatches(pos, literal, 0, literal.length())) {
                throw new IllegalStateException("Expected '" + literal + "' at position " + pos);
            }
            pos += literal.length();
            return value;
        }
    }
}
