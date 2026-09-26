package com.fari.connection;

import java.io.ByteArrayOutputStream;
import java.net.StandardProtocolFamily;
import java.net.URLEncoder;
import java.net.UnixDomainSocketAddress;
import java.nio.ByteBuffer;
import java.nio.channels.SocketChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Discovers running Docker containers opted into monitoring (label {@value #OPT_IN_LABEL}) with
 * 2+ published TCP ports (candidates for connection method 6 — see
 * docs/specs/jvm-connection-methods.md), by talking to the local Docker daemon's Engine API over
 * its Unix domain socket. No docker-java library, no shelled-out CLI (pillar 2 — lightweight, and
 * no dependency on the docker binary being on PATH or its output format).
 */
public final class DockerDiscovery {

    private static final String DEFAULT_SOCKET_PATH = "/var/run/docker.sock";

    /** Opt-in label — see docs/specs/jvm-connection-methods.md method 6 for why this exists. */
    public static final String OPT_IN_LABEL = "jvm-monitor.enabled=true";

    private DockerDiscovery() {
    }

    public static List<DockerContainerInfo> listContainers() {
        Path socketPath = resolveSocketPath();
        String filters = "{\"label\":[\"" + OPT_IN_LABEL + "\"]}";
        String query = URLEncoder.encode(filters, StandardCharsets.UTF_8);
        String body = httpGet(socketPath, "/containers/json?filters=" + query);
        Object parsed = MinimalJson.parse(body);
        if (!(parsed instanceof List<?> containers)) {
            throw new ConnectionException("Unexpected response from Docker daemon at " + socketPath);
        }
        List<DockerContainerInfo> result = new ArrayList<>();
        for (Object entry : containers) {
            if (!(entry instanceof Map<?, ?> map)) {
                continue;
            }
            DockerContainerInfo info = toContainerInfo(map);
            if (info.publishedTcpPorts().size() >= 2) {
                result.add(info);
            }
        }
        return result;
    }

    private static Path resolveSocketPath() {
        String dockerHost = System.getenv("DOCKER_HOST");
        if (dockerHost != null && !dockerHost.isBlank()) {
            return Path.of(dockerHost.replaceFirst("^unix://", ""));
        }
        return Path.of(DEFAULT_SOCKET_PATH);
    }

    @SuppressWarnings("unchecked")
    private static DockerContainerInfo toContainerInfo(Map<?, ?> map) {
        String id = String.valueOf(map.get("Id"));
        String shortId = id.length() > 12 ? id.substring(0, 12) : id;
        Object namesValue = map.get("Names");
        List<Object> names = namesValue instanceof List<?> l ? (List<Object>) l : List.of();
        String name = names.isEmpty() ? shortId : names.get(0).toString().replaceFirst("^/", "");
        String image = String.valueOf(map.get("Image"));

        List<Integer> publishedTcpPorts = new ArrayList<>();
        Object portsValue = map.get("Ports");
        List<Object> ports = portsValue instanceof List<?> l ? (List<Object>) l : List.of();
        for (Object portEntry : ports) {
            if (!(portEntry instanceof Map<?, ?> port)) {
                continue;
            }
            Object type = port.get("Type");
            Object publicPort = port.get("PublicPort");
            if ("tcp".equals(type) && publicPort instanceof Double d) {
                publishedTcpPorts.add(d.intValue());
            }
        }
        return new DockerContainerInfo(shortId, name, image, publishedTcpPorts);
    }

    private static String httpGet(Path socketPath, String path) {
        UnixDomainSocketAddress address = UnixDomainSocketAddress.of(socketPath);
        try (SocketChannel channel = SocketChannel.open(StandardProtocolFamily.UNIX)) {
            channel.connect(address);
            String request = "GET " + path + " HTTP/1.1\r\nHost: docker\r\nConnection: close\r\n\r\n";
            channel.write(ByteBuffer.wrap(request.getBytes(StandardCharsets.UTF_8)));

            ByteArrayOutputStream raw = new ByteArrayOutputStream();
            ByteBuffer buf = ByteBuffer.allocate(8192);
            int read;
            while ((read = channel.read(buf)) != -1) {
                raw.write(buf.array(), 0, read);
                buf.clear();
            }
            return parseHttpResponse(raw.toString(StandardCharsets.UTF_8));
        } catch (java.nio.file.AccessDeniedException e) {
            throw new ConnectionException("Can't read " + socketPath
                    + " — add your user to the docker group: sudo usermod -aG docker $USER (then log out/in).", e);
        } catch (java.io.IOException e) {
            if (e.getMessage() != null && e.getMessage().toLowerCase(java.util.Locale.ROOT).contains("permission denied")) {
                throw new ConnectionException("Can't read " + socketPath
                        + " — add your user to the docker group: sudo usermod -aG docker $USER (then log out/in).", e);
            }
            throw new ConnectionException("Could not reach Docker daemon at " + socketPath + " — is Docker running?", e);
        }
    }

    private static String parseHttpResponse(String raw) {
        int headerEnd = raw.indexOf("\r\n\r\n");
        if (headerEnd < 0) {
            throw new ConnectionException("Malformed response from Docker daemon");
        }
        String headers = raw.substring(0, headerEnd);
        String body = raw.substring(headerEnd + 4);

        String statusLine = headers.lines().findFirst().orElse("");
        if (!statusLine.contains(" 200 ")) {
            throw new ConnectionException("Docker daemon returned an error: " + statusLine);
        }

        boolean chunked = headers.toLowerCase(java.util.Locale.ROOT).contains("transfer-encoding: chunked");
        return chunked ? dechunk(body) : body;
    }

    private static String dechunk(String body) {
        StringBuilder result = new StringBuilder();
        int pos = 0;
        while (pos < body.length()) {
            int lineEnd = body.indexOf("\r\n", pos);
            if (lineEnd < 0) {
                break;
            }
            int size = Integer.parseInt(body.substring(pos, lineEnd).trim(), 16);
            if (size == 0) {
                break;
            }
            int chunkStart = lineEnd + 2;
            result.append(body, chunkStart, chunkStart + size);
            pos = chunkStart + size + 2; // skip trailing \r\n after the chunk
        }
        return result.toString();
    }
}
