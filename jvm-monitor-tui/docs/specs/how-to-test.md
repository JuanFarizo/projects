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
cd /Users/juan.farizo/Documents/projects/jvm-monitor-tui
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
cd /Users/juan.farizo/Documents/projects/jvm-monitor-tui
mvn -q compile exec:java
```
Press `n` (Add Remote). Alias: anything. Host: `127.0.0.1`. Port: `9010`.
Leave Auth = None. Enter through the fields to submit — should land on
Overview showing SleepyMain's metrics.

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
- Left/Right on the Connections screen switches focus between the local
  processes panel and the saved remotes panel.
- Type an alias/host containing `m`, `t`, `g`, `c`, `d`, `x`, `1`, or `2`
  (the letters that double as global navigation shortcuts elsewhere in the
  app) into a text field — it should type normally, not get swallowed as a
  screen-switch shortcut.
