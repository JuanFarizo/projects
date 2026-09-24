# jvm-monitor-tui

Terminal UI for monitoring JVM processes, local and remote.

**Tech stack:** Java 25 · TamboUI 0.5.0-SNAPSHOT

## Features (pending)

- [ ] Local JVM attach and process list
- [ ] Remote JMX connection (direct, SSH tunnel, SSH SOCKS proxy)
- [ ] SSH jcmd/jstat data source (no JMX)
- [ ] Docker container JVM connection
- [ ] Heap / GC metrics view
- [ ] Thread view
- [ ] Native image packaging

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
  JvmMonitorTui.java             Entry point and ToolkitApp subclass — screen
                                  switching, key routing, connect/disconnect flow

com.fari.connection              Connection Layer (docs/specs/architecture.md)
  ConnectionHandle.java           Abstraction the Metrics Layer depends on
  LocalAttachConnection.java      VirtualMachine.attach + local JMX management agent
  ProcessDiscovery.java           VirtualMachine.list() — no attach performed
  LocalProcessInfo.java           PID + display name record
  ConnectionException.java

com.fari.metrics                 Metrics Layer — programmed to an abstraction,
                                  JMX polling is the default (and only) implementation
  MetricsSource.java               start()/snapshot()/close()
  JmxPollingMetricsSource.java     background poll loop, volatile snapshot handoff
  MetricsSnapshot.java             top-level immutable snapshot record
  HeapSnapshot.java / CpuSnapshot.java / GcSnapshot.java / GcCollectorStat.java
  ThreadSnapshot.java / VmInfoSnapshot.java / ConnectionStatus.java

com.fari.ui                      UI Layer (TamboUI ToolkitApp), one class per screen
  ConnectionsScreen.java           local JVM picker (process/connection table)
  AddRemoteDialogScreen.java       static shell only — no remote transports yet
  OverviewScreen.java              2x2 Heap/CPU/GC/Threads grid + VM Info strip
  Theme.java                       color palette constants from the design mock

docs/specs/                       Source of truth — read before changing behavior
  requirements.md, architecture.md, jvm-connection-methods.md,
  ui-dsl-api-choice.md, open-questions.md, ui-view/
```
