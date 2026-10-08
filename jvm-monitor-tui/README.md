# jvm-monitor-tui

Terminal UI for monitoring JVM processes, local and remote.

**Tech stack:** Java 25 · TamboUI 0.5.0-SNAPSHOT · JSch (SSH)

## Features

**Connection methods** (see [docs/specs/jvm-connection-methods.md](docs/specs/jvm-connection-methods.md))

- [x] Local attach and process list
- [x] Direct remote JMX (optional username/password)
- [x] SSH `-L` tunnel (password or key auth, strict `~/.ssh/known_hosts` check)
- [x] Docker local containers (discovery via Docker Engine API, label `jvm-monitor.enabled=true`)
- [x] Saved remote connections: add, edit, delete, reconnect. Secrets are never persisted.
- [ ] SSH SOCKS proxy
- [ ] SSH jcmd/jstat data source (no JMX)

**Screens**

- [x] Connections: local processes, Docker containers, saved remotes
- [x] Overview: Heap / CPU / GC / Threads grid + VM info
- [x] Classes
- [x] Memory
- [x] Threads
- [x] GC log

**Packaging**

- [ ] Native image (`native` Maven profile pending)

Saved connections live in `~/.config/jvm-monitor-tui/connections.json`.

## Requirements

- **JDK 25** (LTS)
- **Maven 3.9+**
- **GraalVM 25** (optional, for native image)

## Build & Run

### JVM

```bash
mvn compile exec:java
```

### JAR

```bash
mvn package -DskipTests
java -jar target/jvm-monitor-tui-1.0-SNAPSHOT.jar
```

### Native Image (GraalVM)

Compile to a standalone native binary for instant startup:

```bash
mvn clean -Pnative package -DskipTests
./target/jvm-monitor-tui
```

> Requires GraalVM 25 as your `JAVA_HOME`. If using SDKMAN: `sdk use java 25.0.2-graalce`
>
> The `native` Maven profile is not yet defined in `pom.xml` — pending.

## Testing connection methods

Manual recipes for remote JMX, SSH tunnel and Docker targets: [docs/specs/how-to-test.md](docs/specs/how-to-test.md).

## Setting Up Shell Access

For quick access from any directory, set up an alias or add the binary to your PATH.

### macOS / Linux

Add an alias to `~/.zshrc` or `~/.bashrc`:

```bash
alias jvmmonitor='/path/to/jvm-monitor-tui'
```

Then reload your shell:

```bash
source ~/.zshrc
```

## Project Structure

```
com.fari
  JvmMonitorTui.java             Entry point and ToolkitApp subclass: screen
                                  switching, key routing, connect/disconnect flow

com.fari.connection              Connection Layer (docs/specs/architecture.md)
  ConnectionHandle.java           Abstraction the Metrics Layer depends on
  LocalAttachConnection.java      VirtualMachine.attach + local JMX management agent
  RemoteJmxConnection.java        Direct remote JMX over RMI
  SshTunnelConnection.java        SSH -L tunnel (JSch) + JMX
  ProcessDiscovery.java           VirtualMachine.list(), no attach performed
  DockerDiscovery.java            Docker Engine API over Unix socket (DOCKER_HOST-aware)
  SavedConnection.java            Saved remote profile record
  SavedConnectionsStore.java      connections.json persistence
  MinimalJson.java                Tiny JSON parser (no extra dependency)
  LocalProcessInfo.java / DockerContainerInfo.java / ConnectionException.java

com.fari.metrics                 Metrics Layer, programmed to an abstraction;
                                  JMX polling is the only implementation
  MetricsSource.java               start()/snapshot()/close()
  JmxPollingMetricsSource.java     background poll loop, volatile snapshot handoff
  MetricsSnapshot.java             top-level immutable snapshot record
  Heap/NonHeap/Cpu/Gc/Thread/Classes/Buffers/VmInfo snapshots, GC pause events,
  class histogram parser, deadlocked-thread info (see docs/specs/metrics.md)

com.fari.ui                      UI Layer (TamboUI ToolkitApp), one class per screen
  ConnectionsScreen.java           local / Docker / saved-remote panels
  AddRemoteDialogScreen.java       add, edit, reconnect remote dialog
  OverviewScreen.java              2x2 Heap/CPU/GC/Threads grid + VM Info strip
  ClassesScreen / MemoryScreen / ThreadsScreen / GcLogScreen
  Theme.java                       color palette constants from the design mock

docs/specs/                       Source of truth — read before changing behavior
  requirements.md, architecture.md, jvm-connection-methods.md, metrics.md,
  how-to-test.md, ui-dsl-api-choice.md, open-questions.md, ui-view/
```
