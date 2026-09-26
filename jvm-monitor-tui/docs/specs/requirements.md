# Requirements

Source of truth for what this app must do and how well it must do it. Every feature/architecture decision aligns with this file.

## Pillars (non-negotiable, in priority order)
1. **TUI JVM monitor** — the feature set itself.
2. **Lightweight** — small footprint: minimal deps, native-image-able, no bundled JVM/app-server-sized runtime assumptions.
3. **Performant** — low idle CPU/memory overhead from the monitor itself; never adds noticeable load to the target JVM or the host running the monitor.

Any design choice that trades pillar 2 or 3 for convenience needs explicit justification recorded here or in the relevant spec doc.

## Functional requirements

### Connections (see [jvm-connection-methods.md](jvm-connection-methods.md))
- Local JVM discovery + attach.
- Direct remote JMX.
- SSH -L tunnel.
- SSH SOCKS proxy.
- SSH + jcmd/jstat (no JMX).
- Docker container JVM — local daemon, remote Docker host out of current scope.
- Saved remote connection profiles (alias, host, port, protocol, auth, SSL/TLS) — see [ui-view mock, screen 2](ui-view/jvm-monitor-tui-implementation-handoff.html).
- Saved remote connections support edit and delete (Connections screen, saved-connections panel only — not local processes): `e` opens the Add Remote form prefilled for editing, `d` deletes after inline confirmation. Both act on the persisted profile only, never on an already-live connection session.

### Metrics
Full catalog with status (implemented / approved / rejected / parked): [metrics.md](metrics.md).

- Heap: used/committed/max, Eden/Old/Survivor breakdown, history (sparkline).
- Non-heap: used/committed/max (aggregate), Code Cache, Compressed Class Space.
- Off-heap buffers: direct/mapped NIO buffer pools (count/used/capacity).
- CPU: process/system/cores, rolling average.
- GC: per-collector count/total time/avg pause, last-pause duration + cause (young vs full split) — not available on connection method 5 (SSH + jcmd/jstat, no JMX), accepted gap.
- Threads: live/daemon/peak/started, state breakdown (RUNNABLE/WAITING/TIMED_WAITING/BLOCKED), deadlock detection, per-thread CPU time (top-N).
- Classes/Metaspace: used/committed/loaded/unloaded, history (sparkline), loaded-class table (name, loader, instances, size), filter/search.
- VM Info/Host: JVM name/version, GC algorithm, arg count, classpath entries, uptime, JIT total compilation time, system load average, physical memory total/free, swap total/free, open file descriptors (Unix-only).

**Non-goals:** heap dump/object histogram analysis, CPU/memory sampling profiler, flame graphs — out of scope, conflicts pillar 2.

Collection mechanism: JMX polling is the default. JFR event streaming stays parked — only add it if polling demonstrably misses events (e.g. short GC pauses) that matter to the UI. GC last-pause duration/cause uses a JMX notification listener alongside the poll loop (still JMX, not JFR) — see [metrics.md](metrics.md) GC section for the implementation approach and the connection-method restriction.

### Screens (see [ui-view mock](ui-view/jvm-monitor-tui-implementation-handoff.html))
1. Connections (process picker + saved remotes).
2. Add Remote Connection (modal).
3. Overview Dashboard (2×2 panel grid: Heap, CPU, GC, Threads + VM Info strip).
4. Classes / Metaspace browser.

Navigation: command-driven, keyboard-only, no mouse affordances, no persistent nav chrome.

### Packaging
- Runnable JAR (`mvn package`).
- Native image via GraalVM (`mvn -Pnative package`) — required for pillar 2, not optional polish.

## Non-functional requirements
- **Lightweight/performant, concretely:** not yet quantified (no startup-time or footprint target set). Fill in once there's something to measure.
- **UI thread safety:** never block or mutate UI state off the render thread.
- **Resilience:** a lost/unreachable connection (remote host drops, SSH tunnel dies, target JVM exits) must degrade the UI to a clear status, never crash the app. A failed connection attempt (bad credentials, refused connection, etc.) must surface its error on the screen the user is actually looking at — e.g. inline in the Add/Edit Remote dialog while it's still open, not only after the dialog is dismissed — and must never discard what the user already typed.
- **No unnecessary dependencies:** every new Maven dependency must be justified against pillar 2 before adding (mirrors [ui-dsl-api-choice.md](ui-dsl-api-choice.md)'s decision-log format).

