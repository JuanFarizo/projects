# Architecture

High-level module/thread layout. Detailed API design happens per-module when implemented; this file only fixes boundaries and the concurrency contract so pieces don't collide later.

## Layers

| Layer | Responsibility |
|---|---|
| UI (TamboUI `ToolkitApp`) | Screens, key events, `TickEvent`-driven render |
| Metrics Layer | Polling scheduler, metric snapshot model |
| Connection Layer | Discovery, attach, JMX/SSH/Docker transports |

Each layer only depends on the one below it — UI depends on Metrics, Metrics depends on Connection, never the reverse.

### Connection Layer
- Covers the methods in [jvm-connection-methods.md](jvm-connection-methods.md): local attach, direct remote JMX, SSH tunnel, SSH SOCKS, SSH+jcmd (no JMX), Docker.
- The Metrics Layer must not care which transport is behind a given connection — exact interface shape not yet decided.
- **SSH -L tunnel, implemented**: `com.fari.connection.SshTunnelConnection`, using `com.github.mwiede:jsch` (maintained JSch fork, pure Java, no native deps). Local port binds must match the target JVM's configured JMX/RMI ports exactly (see method 3's spec entry). Host key verification is strict against the user's own `~/.ssh/known_hosts` — no separate trust store, no disabled verification. Supports password or private-key-file SSH auth; does not cover JMX-level auth (`jmxremote.authenticate=true`) on top of the tunnel, same as method 2's optional auth layer but not wired through the SSH path yet.

#### Saved-connection persistence
- Format: JSON. One file, array of connection profiles (id, alias, host, port, username, connection method).
- Location: `~/.config/jvm-monitor-tui/connections.json`.
- **Password is never persisted.** Add/Edit Remote dialogs prompt for it on each connect (or leave it blank on edit, re-entered when connecting); held in memory only for the life of that connection.
- Rationale: avoids owning an encryption-at-rest problem (key storage) or an OS-keychain dependency, whose native-image compatibility is unresearched (pillar 2 risk, same class as `jdk.attach` in [open-questions.md](open-questions.md)). No secret ever touches disk, so there's nothing to protect.
- **Implemented** (`com.fari.connection.SavedConnectionsStore`, alongside the Direct Remote JMX connection method): hand-rolled JSON reader/writer, no library dependency — the shape is a narrow enough flat array-of-flat-objects that pulling in Jackson/Gson for it would be a pillar-2 violation. Atomic write (temp file + rename).
- **Identity**: each profile has a stable `id` (UUID), generated on first save and unchanged across edits — this is what `update`/`delete` key off, independent of alias/host/port. Entries from before the `id` field existed get one generated on load and persisted on the next save (no explicit migration step; acceptable pre-1.0 with no external format consumers).
- `upsert` (dedupe key: alias, host, port) still runs on every successful connect, guarding against accidental duplicate profiles when adding. `update`/`delete` (both id-keyed) back the Connections screen's edit (`e`) and delete (`d`) actions on a saved connection, which only ever change/remove the persisted profile — they never affect an already-live connection session.

### Metrics Layer
- Programmed to an abstraction (a `MetricsSource`-style interface producing snapshots), not to a concrete collection mechanism — swapping mechanisms must not require changes in the UI Layer or elsewhere in the Metrics Layer.
- **Default, always-available implementation: JMX polling.** Works over any `MBeanServerConnection`, i.e. every connection method in [jvm-connection-methods.md](jvm-connection-methods.md).
- **Optional implementation: JFR `RecordingStream`.** Only for connection methods where it doesn't require a file-dump-and-parse step (realistically: local attach). Whether a given connection method supports it is a Connection Layer concern, not something the rest of the app needs to know about. Not built now — the interface just has to not preclude adding it later.
- Must not run on the render thread — how it hands data to the UI Layer is not yet decided.

### UI Layer
- `dev.tamboui.toolkit.app.ToolkitApp`, retained-mode (`render()` returns declarative `Element` tree) — decision already made in [ui-dsl-api-choice.md](ui-dsl-api-choice.md).
- Screens map 1:1 to [ui-view mock](ui-view/jvm-monitor-tui-implementation-handoff.html): Connections, Add Remote, Overview, Classes/Metaspace.
- Redraw driven by `TickEvent` (timer).

## Concurrency constraint
- Render thread is the single owner of UI state (TamboUI constraint).
- Metrics Layer must never block or mutate UI state off the render thread.
- Everything else — handoff mechanism, threading model per connection, snapshot data shape — is an open design question, not decided yet.

## Open questions
See [open-questions.md](open-questions.md).
