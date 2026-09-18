# jvm-monitor-tui

Terminal UI for monitoring JVM processes (local and remote) — an `htop`/VisualVM analog for the terminal.

**Three pillars, in priority order:** (1) JVM monitor TUI features, (2) **lightweight**, (3) **performant**. Every change trades against these — see [docs/spec/requirements.md](docs/spec/requirements.md) for the non-negotiables.

## Source of truth

`docs/spec/` is authoritative. Any requirement, architecture decision, or screen behavior must align with what's there — treat it as spec, not as background reading.

- [requirements.md](docs/spec/requirements.md) — functional + non-functional requirements, pillars.
- [architecture.md](docs/spec/architecture.md) — layers (Connection / Metrics / UI), concurrency contract.
- [jvm-connection-methods.md](docs/spec/jvm-connection-methods.md) — supported connection methods, implementation order.
- [ui-dsl-api-choice.md](docs/spec/ui-dsl-api-choice.md) — why `ToolkitApp` (retained-mode) over low-level `Backend`/`Frame`.
- [ui-view/design_handoff_jvm_monitor_tui/](docs/spec/ui-view/design_handoff_jvm_monitor_tui/README.md) — screen mocks (Connections, Add Remote, Overview, Classes/Metaspace).

Before implementing a feature: check these first. If a request conflicts with them, flag the conflict instead of silently resolving it.

**Never assume.** If something isn't clear or decided in `docs/spec/`, ask the user — don't guess or default. Once the user resolves the gap, update the relevant spec file only after they've reviewed the change.

## Tech stack

- **Java 25** (LTS), Maven 3.9+
- **TamboUI 0.5.0-SNAPSHOT** (`tamboui-toolkit`, `tamboui-jline3-backend`, `tamboui-css`) — retained-mode TUI toolkit
- **GraalVM 25** for native-image packaging (pillar 2 — not optional polish)
- JUnit 5 for tests

## Structure

- `src/main/java/com/fari/JvmMonitorTui.java` — entry point (skeleton, not yet implemented)
- `docs/spec/` — source of truth, see above

## Build & run

```bash
mvn compile exec:java          # runs com.fari.JvmMonitorTui
mvn package -DskipTests && java -jar target/jvm-monitor-tui-1.0-SNAPSHOT.jar
mvn clean -Pnative package -DskipTests   # native profile not yet defined — pending
```
</content>
