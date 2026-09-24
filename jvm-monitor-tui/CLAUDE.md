# jvm-monitor-tui

Terminal UI for monitoring JVM processes (local and remote) — an `htop`/VisualVM analog for the terminal.

**Three pillars, in priority order:** (1) JVM monitor TUI features, (2) **lightweight**, (3) **performant**. Every change trades against these — see [docs/specs/requirements.md](docs/specs/requirements.md) for the non-negotiables.

## Source of truth

`docs/specs/` is authoritative. Any requirement, architecture decision, or screen behavior must align with what's there — treat it as spec, not as background reading.

- [requirements.md](docs/specs/requirements.md) — functional + non-functional requirements, pillars.
- [architecture.md](docs/specs/architecture.md) — layers (Connection / Metrics / UI), concurrency contract.
- [jvm-connection-methods.md](docs/specs/jvm-connection-methods.md) — supported connection methods, implementation order.
- [ui-dsl-api-choice.md](docs/specs/ui-dsl-api-choice.md) — why `ToolkitApp` (retained-mode) over low-level `Backend`/`Frame`.
- [ui-view/jvm-monitor-tui-implementation-handoff.html](docs/specs/ui-view/jvm-monitor-tui-implementation-handoff.html) — screen mocks (Connections, Add Remote, Overview, Classes/Metaspace).

Before implementing a feature: check these first. If a request conflicts with them, flag the conflict instead of silently resolving it.

**Never assume.** If something isn't clear or decided in `docs/specs/`, ask the user — don't guess or default. Once the user resolves the gap, update the relevant spec file only after they've reviewed the change.

## Code comments

Comment only when the code isn't self-explanatory: a hidden constraint, a library quirk, a non-obvious workaround, or a decision a reader would otherwise question. Never restate what the code already says.

Keep it short — 1-2 lines. If it takes a paragraph to justify one line of code, fix the code (rename, extract, restructure) instead of writing a longer comment.

## Tech stack

- **Java 25** (LTS), Maven 3.9+
- **TamboUI 0.5.0-SNAPSHOT** (`tamboui-toolkit`, `tamboui-jline3-backend`, `tamboui-css`) — retained-mode TUI toolkit
- **GraalVM 25** for native-image packaging (pillar 2 — not optional polish)
- JUnit 5 for tests

## Structure

- `src/main/java/com/fari/JvmMonitorTui.java` — entry point, `ToolkitApp` (screens, navigation, key handling)
- `src/main/java/com/fari/connection/` — Connection layer (local attach, remote handles)
- `src/main/java/com/fari/metrics/` — Metrics layer (JMX polling, snapshots)
- `src/main/java/com/fari/ui/` — UI layer (screens, theme)
- `docs/specs/` — source of truth, see above

## UI verification

This is an interactive terminal UI (JLine3 backend, raw terminal mode) — Claude cannot run it and visually confirm rendering (layout, colors, widget behavior) the way it would for a web UI. After any UI-layer change, state that explicitly instead of claiming the change looks right: confirm the build/tests pass, then say the render itself needs the user's own visual check in a terminal.

## Build & run

```bash
mvn compile exec:java          # runs com.fari.JvmMonitorTui
mvn package -DskipTests && java -jar target/jvm-monitor-tui-1.0-SNAPSHOT.jar
mvn clean -Pnative package -DskipTests   # native profile not yet defined — pending
```
</content>
