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

#### Saved-connection persistence
- Format: JSON. One file, array of connection profiles (host, port, username, display name, connection method).
- Location: `~/.config/jvm-monitor-tui/connections.json`.
- **Password is never persisted.** Add Remote dialog prompts for it on each connect; held in memory only for the life of that connection.
- Rationale: avoids owning an encryption-at-rest problem (key storage) or an OS-keychain dependency, whose native-image compatibility is unresearched (pillar 2 risk, same class as `jdk.attach` in [open-questions.md](open-questions.md)). No secret ever touches disk, so there's nothing to protect.

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
