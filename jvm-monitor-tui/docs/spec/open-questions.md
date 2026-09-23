# Open Questions

Unresolved decisions and known limitations, tracked here so they aren't
silently assumed. Items move out once resolved (with the resolution recorded
in the relevant spec file) or intentionally accepted as a permanent tradeoff.

## Unresolved decisions

Moved from architecture.md — the Connection Layer interface shape, the
Metrics→UI handoff mechanism, and the metrics snapshot data model are now
settled (see architecture.md and the `com.fari.connection`/`com.fari.metrics`
packages); these remain open:

- **Threading model for multiple simultaneous connections.** The current
  scaffold supports exactly one active connection/MetricsSource at a time
  (Connections → Overview → disconnect). If the app ever needs to monitor
  multiple JVMs concurrently (e.g. a multi-pane view), the poll-thread-per-
  connection model needs revisiting for thread/resource limits.
- **Classes/Metaspace per-class table JMX feasibility.** Standard
  `java.lang.management` MXBeans (`MemoryPoolMXBean`, `ClassLoadingMXBean`)
  give aggregate Metaspace/Classloading stats (used/committed/loaded/unloaded)
  without issue. A per-class table with instance counts + retained size (the
  requirement for the Classes/Metaspace screen) needs HotSpot-specific
  diagnostic commands (`com.sun.management.DiagnosticCommandMBean`,
  `gcClassHistogram`-equivalent) that aren't part of the standard MXBean
  surface. Feasibility of those diagnostic-command MBeans under a GraalVM
  native-image build (pillar 2's packaging goal) is unresearched. The
  Classes/Metaspace screen itself is not built yet — this blocks starting
  it, not anything currently in the codebase.

## Known risks / backlog

Not decisions blocking anything currently built — known limitations in the
JMX-polling MetricsSource, filed here as debt to revisit rather than fixed
now:

1. `com.sun.management.OperatingSystemMXBean.getCpuLoad()` vs the deprecated
   `getSystemCpuLoad()` — the code uses the JDK-25-correct non-deprecated
   name; revisit if ever targeting older JDKs.
2. Eden/Old/Survivor breakdown in `JmxPollingMetricsSource` matches
   `MemoryPoolMXBean.getName()` against HotSpot-convention substrings
   ("Eden", "Old"/"Tenured", "Survivor") — not a stable contract. Blank on
   non-HotSpot JVMs or GC implementations with different pool names (e.g.
   ZGC, Shenandoah).
3. `ThreadMXBean.getThreadInfo(long[])` runs on every poll tick — the
   priciest call in the loop. At the current 1000ms interval this is fine in
   practice, but on a target JVM with a very large thread count it could
   itself become "noticeable load on the target JVM" (pillar 3). No
   throttling/backoff implemented; first place to optimize if profiling
   shows it.
4. GraalVM native-image compatibility is unresearched for the whole JMX-based
   collection surface, not just attach:
   `com.sun.tools.attach.VirtualMachine.attach()` (`jdk.attach` module);
   the growing set of `ManagementFactory.newPlatformMXBeanProxy`-built dynamic
   proxies in `JmxPollingMetricsSource` (one per MXBean interface — memory,
   memory pool, OS, unix-OS, GC, thread, runtime, class-loading, compilation,
   buffer-pool); the live `NotificationEmitter`/`addNotificationListener`
   registration used for GC last-pause events; and
   `com.sun.management.GarbageCollectionNotificationInfo.from(CompositeData)`,
   which decodes `javax.management.openmbean.CompositeData` via `OpenType`
   item-name reflection. Native-image packaging is out of scope for the
   current pass, but all of this is core functionality and will need a
   GraalVM tracing-agent run (exercising the notification listener at least
   once) and the resulting `proxy-config.json`/reflect-config before
   native-image packaging can ship.
5. `RuntimeMXBean.getClassPath()` returns an empty string on modulepath-only
   launches — the VM Info panel's classpath entry count shows 0 in that case
   rather than something clearer.
6. The 1000ms poll interval (`JmxPollingMetricsSource.POLL_INTERVAL_MS`) is a
   placeholder, not derived from a measured footprint budget — requirements.md
   itself notes pillars 2/3 aren't quantified yet. Revisit once there's a
   target.
7. Attaching to the monitor's own JVM process fails
   (`ConnectionException: Failed to attach to process <pid>`) unless the
   target JVM is launched with `-Djdk.attach.allowAttachSelf=true` — this is
   a JDK-level restriction on `VirtualMachine.attach`, not a bug, but it's a
   confusing first-run experience (the monitor's own PID is always visible
   and selectable in its own process list). Worth a clearer inline message
   distinguishing "self-attach blocked" from other attach failures.
