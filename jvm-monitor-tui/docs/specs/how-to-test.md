# How to Test

Manual verification recipes for connection methods that need a live target
JVM. Claude cannot drive a raw-terminal TUI itself (see CLAUDE.md's "UI
verification" rule) — these are for you to run locally.

## Direct Remote JMX (connection method 2)

You don't need an actual remote host — point the monitor at a JVM on
`127.0.0.1` with remote JMX enabled. The repo already has a trivial
long-lived target for this: `src/test/java/com/fari/metrics/SleepyMain.java`
(`Thread.sleep(Long.MAX_VALUE)`, also used by
`JmxPollingMetricsSourceCollectionTest`).

Two terminals: one runs the target JVM, the other runs the monitor.

### Without auth

**Terminal 1 — target JVM:**
```bash
cd /path/to/jvm-monitor-tui
mvn -q test-compile
java -cp target/test-classes \
  -Dcom.sun.management.jmxremote \
  -Dcom.sun.management.jmxremote.port=9010 \
  -Dcom.sun.management.jmxremote.rmi.port=9010 \
  -Dcom.sun.management.jmxremote.ssl=false \
  -Dcom.sun.management.jmxremote.authenticate=false \
  -Djava.rmi.server.hostname=127.0.0.1 \
  com.fari.metrics.SleepyMain
```

**Terminal 2 — the monitor:**
```bash
cd /path/to/jvm-monitor-tui
mvn -q compile exec:java
```
Press `n` (Add Remote). Alias: anything. Host: `127.0.0.1`. Port: `9010`.
Leave Auth = None.

### With auth

JMX's built-in password-file auth needs two files set up first, and the
password file **must** be `chmod 600` or the target JVM refuses to start
(`java.io.IOException: Password file read access must be restricted`):

```bash
echo "monitor readwrite" > /tmp/jmxremote.access
echo "monitor secret123" > /tmp/jmxremote.password
chmod 600 /tmp/jmxremote.password /tmp/jmxremote.access
```

**Terminal 1 — target JVM** (same as above, but swap the `authenticate`
line for these three):
```bash
java -cp target/test-classes \
  -Dcom.sun.management.jmxremote \
  -Dcom.sun.management.jmxremote.port=9010 \
  -Dcom.sun.management.jmxremote.rmi.port=9010 \
  -Dcom.sun.management.jmxremote.ssl=false \
  -Dcom.sun.management.jmxremote.authenticate=true \
  -Dcom.sun.management.jmxremote.password.file=/tmp/jmxremote.password \
  -Dcom.sun.management.jmxremote.access.file=/tmp/jmxremote.access \
  -Djava.rmi.server.hostname=127.0.0.1 \
  com.fari.metrics.SleepyMain
```

**Terminal 2 — the monitor:** same as above, but in Add Remote toggle
Auth to "Username & Password" (Left/Right on the Auth row), username
`monitor`, password `secret123`.

## Docker, local (connection method 6)

Any container is fine as long as it publishes both ports and sets the JMX flags — no image
rebuild needed, `JAVA_TOOL_OPTIONS` is picked up by a plain `java -jar`/`java -cp` entrypoint.
Verified: `-Djava.rmi.server.hostname=localhost` works here because the monitor and the Docker
daemon are the same machine — Docker's `-p` publish reaches the container via the host's own
loopback too, no need to hunt for a LAN IP.

**Terminal 1 — throwaway target container** (swap `my-app-image` for any real app image — the
flags are all that matters):
```bash
docker run -d --name jmxtest -p 9010:9010 -p 9011:9011 \
  --label jvm-monitor.enabled=true \
  -e JAVA_TOOL_OPTIONS="-Dcom.sun.management.jmxremote \
    -Dcom.sun.management.jmxremote.port=9010 \
    -Dcom.sun.management.jmxremote.rmi.port=9011 \
    -Djava.rmi.server.hostname=localhost \
    -Dcom.sun.management.jmxremote.authenticate=false \
    -Dcom.sun.management.jmxremote.ssl=false" \
  my-app-image
```

**Terminal 2 — the monitor:**
```bash
mvn -q compile exec:java
```
Left/Right to the DOCKER CONTAINERS panel. The labeled container should appear; press `r` if it
was already running before the monitor started. Enter connects.

**Negative cases:**
- A container *without* the label (e.g. `postgres`, `minio`) should never appear, even with 2+
  published ports.
- Labels are set at container creation and can't be edited in place: `docker rm -f jmxtest`,
  recreate it with the same `docker run` command but *without* the `--label` flag, restart the
  monitor, confirm it no longer appears in DOCKER CONTAINERS.
- `docker rm -f jmxtest` when done.

### Checklist while you're in there

- After a successful connect, back out to Connections (`1`) — the profile
  should now appear under "SAVED REMOTE CONNECTIONS".
- `~/.config/jvm-monitor-tui/connections.json` should have the entry on
  disk. For the auth-enabled test, confirm no password ever landed in it:
  `grep -i password ~/.config/jvm-monitor-tui/connections.json` should find
  nothing.
- Reconnecting a saved entry: the no-auth profile should reconnect
  immediately on Enter; the auth profile should show the inline
  username/password re-prompt instead.
- Left/Right on the Connections screen cycles focus through all three
  panels — local processes, Docker containers, saved remotes.
- A Docker connection never gets saved: after connecting to `jmxtest`, back
  out to Connections (`1`) and confirm it does **not** appear under "SAVED
  REMOTE CONNECTIONS" or in `connections.json` — unlike Direct Remote JMX
  above, Docker rows are ephemeral/rediscovered, not persisted profiles.
- Type an alias/host containing `m`, `t`, `g`, `c`, `d`, `x`, `1`, or `2`
  (the letters that double as global navigation shortcuts elsewhere in the
  app) into a text field — it should type normally, not get swallowed as a
  screen-switch shortcut.
