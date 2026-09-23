# Metrics

Full catalog of every metric this app collects or will collect, classified by
category, with source API and status. Companion to
[requirements.md](requirements.md)'s Metrics section, which stays a summary —
this file is the detailed reference. Closes the metrics-discovery pass: what's
collected today, what was researched and approved to add, and what's
explicitly out of scope.

## Status legend
- [x] Implemented — see `JmxPollingMetricsSource`
- [+] Approved, not yet implemented
- [-] Considered, rejected (with reason)
- [?] Parked — needs more discussion before a decision

## Display philosophy
Stated once so future metrics get a widget assigned by rule, not re-litigated
case by case: **a metric that has a known ceiling it can approach (max heap,
100%/core-count CPU, fd limit, swap capacity) gets a precision-first
widget — `Chart` (labeled axis) or `LineGauge` (ratio-to-ceiling).
A metric with no ceiling, or where the shape/outlier matters more than the
exact number (a GC pause spike, a categorical snapshot), gets the widget
built for that shape instead — `Chart`/`SCATTER` for per-event outliers,
`BarChart`/`BarGroup`/`Table` for categorical/ranked snapshots.** Applying
this: does the metric have a limit it's approaching → `Chart`/`LineGauge`;
is it a one-off event whose outliers matter → `Chart`/`SCATTER`; is it a
snapshot across named categories → `BarChart`/`BarGroup`/`Table`.

**Revised during UI implementation — screen space overrides the widget
choice, not just the metric shape:** the rule above picks the right *shape*
of widget, but the Overview screen's 2x2 grid gives each panel only a few
rows, and `Chart` needs room for axis labels plus a legend on top of the
actual line — under that constraint it rendered as an unreadable sliver.
Time-series metrics that live in the 2x2 grid (Heap, CPU) use `Sparkline` /
`DualSparkline` instead, with `showYAxis(true)` + `xLabels(...)` kept so the
X/Y reference isn't lost, just compacted. The full `Chart` (axis titles,
legend, more headroom) is reserved for the one-screen-per-metric detail
views (Memory, Classes/Metaspace, GC Log), which have the room for it.
Also revised: Heap/CPU/Metaspace charts (both `Chart` and `Sparkline` forms)
auto-scale their Y-axis to the visible data window instead of pinning it to
the ceiling (max heap / 100%). Fixed-at-ceiling meant a lightly-loaded JVM's
line sat static on the bottom row — informative for "how close to the
ceiling" but useless for seeing actual movement, and movement is what these
panels are for at a glance. The direct ceiling comparison is still available
from the plain-text max/committed numbers next to each chart.

## Heap
- Used / committed / max — [x] `MemoryMXBean.getHeapMemoryUsage()`
- Eden / Old / Survivor breakdown — [x] `MemoryPoolMXBean`, name-substring match
  (HotSpot-only — see open-questions.md known risk #2)
- History, 40-sample sparkline — [x], separate used/committed histories
- **Display:** used/committed over time, auto-scaled Y-axis (see Display
  philosophy revision above) — Overview: `DualSparkline` (top=used,
  bottom=committed), `showYAxis(true)`, `xLabels("-40s","now")`. Memory
  detail screen: full `Chart`, 2 LINE datasets. Eden/Old/Survivor — see
  Non-heap's combined `BarGroup` below.

## Non-heap
- Used / committed / max (aggregate) — [x] `MemoryMXBean.getNonHeapMemoryUsage()`
- Code Cache — [x] `MemoryPoolMXBean`, name-substring match. Since JDK 9 Code
  Cache is segmented into several `CodeHeap '...'` pools (non-nmethods/
  profiled/non-profiled), not one pool named "Code Cache" — matched and
  summed across all of them (same risk class as Eden/Old/Survivor matching).
- Compressed Class Space — [x] `MemoryPoolMXBean`
- Metaspace — spec'd separately under Classes/Metaspace (below)
- **Display:** pool breakdown at a point in time (Eden/Old/Survivor + Code
  Cache/Compressed Class Space) — one `BarGroup`, one bar per pool via
  `Bar.of(value, label)` for exact-value labels. Categorical snapshot, no
  time dimension, so `Chart`/`Sparkline` don't apply here.

## Off-heap buffers
- Direct buffer pool: count / used / capacity — [x]
  `BufferPoolMXBean` (`java.nio:type=BufferPool,name=direct`)
- Mapped buffer pool: count / used / capacity — [x] same bean, `name=mapped`
- Why: common leak source in NIO/Netty-style apps, invisible without this.
- **Display:** plain text (count/used/capacity per pool) — two pools, three
  numbers each, no trend or comparison widget earns its cost here yet.
  Revisit if buffer leaks turn out to need trend visibility in practice.

## CPU
- Process load — [x] `OperatingSystemMXBean.getProcessCpuLoad()`
- System load — [x] `getCpuLoad()`
- Cores — [x] `getAvailableProcessors()`
- Rolling average (60s) — [x]
- History — [x]
- **Display:** process load over time, auto-scaled Y-axis (see Display
  philosophy revision above) — Overview: `Sparkline`, `showYAxis(true)`,
  `xLabels("-60s","now")`, history pre-rounded to whole percent (`Sparkline`'s
  Y-axis label shows the raw value, no formatter hook, unlike `DualSparkline`).
  **System load is not charted** — it's context for the process number, not
  a metric worth its own trend widget or a process-vs-system comparison
  chart; shown as a plain current-value number alongside the sparkline.

## GC
- Per-collector count / total time / avg pause — [x] `GarbageCollectorMXBean`
- **Display:** `Table` — several named collectors × several numeric columns,
  same shape GC's per-collector stats already are, no change from what's
  proven to work for this shape.
- Last-pause duration + cause (young vs full split) — [x]
  `com.sun.management.GarbageCollectionNotificationInfo` via a JMX
  `NotificationListener` registered on the GC `ObjectName`s (still JMX, not
  JFR — no conflict with the parked-JFR decision). Implementation lives
  inside `JmxPollingMetricsSource` (not a separate `MetricsSource` — see
  Design note below): a `volatile GcPauseEvent lastGcEvent` field, written
  only by the notification callback thread, read into `GcSnapshot` on each
  poll tick. Single-writer-per-field, no lock needed — same
  plain-`volatile`/no-synchronization contract architecture.md already uses.
  Availability is modeled as a real tri-state (`GcPauseAvailability`:
  AVAILABLE / PENDING_FIRST_EVENT / UNAVAILABLE), driven by a
  `ConnectionHandle.supportsGcNotifications()` capability flag (default
  `true`, ready for method 5 to override once it's built).
  **Connection-method restriction:** requires a real `MBeanServerConnection`.
  Available on methods 1–4 and 6 in
  [jvm-connection-methods.md](jvm-connection-methods.md) (local attach,
  direct remote JMX, SSH -L tunnel, SSH SOCKS, Docker). **Not available on
  method 5 (SSH + jcmd/jstat, no JMX)** — accepted gap, not blocking: methods
  1–4/6 cover the large majority of use cases, and method 5 has no
  JMX-notification equivalent to fall back to (a jstat-diff approximation
  would lose the cause string and per-event before/after memory anyway, so
  it wouldn't recover the actual value). `GcSnapshot`/`GcPauseEvent` must
  model "unavailable for this connection" as a real state, not an edge case.
- **Display:** `Chart` with `GraphType.SCATTER` — one point per GC event,
  x=time, y=pause ms. This is the metric the tail-latency argument was
  built on — averaging or a smoothed trend line would hide the very outlier
  this metric exists to surface, so a scatter of individual events is the
  only shape that actually serves the purpose. Last-pause value on its own
  (duration/cause/generation, most recent) is a single event, not a series —
  plain text, not a widget.

## Threads
- Live / daemon / peak / started — [x] `ThreadMXBean`
- State breakdown — [x] `getThreadInfo(long[])` (flagged cost, open-questions.md
  known risk #3)
- Deadlock detection — [x] `findDeadlockedThreads()` (covers both monitor and
  ownable-synchronizer deadlocks, so `findMonitorDeadlockedThreads()` isn't
  additionally called); surfacing as a UI alert not yet built
- Per-thread CPU time, top-N table — [x] `getThreadCpuTime(long[])` against the
  same thread-ID array the state breakdown already enumerates — see design
  note below. N=10, kept via a bounded min-heap (`PriorityQueue`) rather than
  sorting every live thread each tick.
- Lock contention (blocked/waited count + time) — [-] rejected for now: needs
  `setThreadContentionMonitoringEnabled(true)`, real per-thread overhead
  stacked on the already-flagged state-breakdown cost. Revisit only if that
  risk is resolved first.
- **Display:** state breakdown (RUNNABLE/WAITING/TIMED_WAITING/BLOCKED/…) —
  `BarChart`, categorical snapshot, no time dimension in the requirement.
  Per-thread CPU top-N — `Table`: a ranked list is consulted for exact
  "which thread, how much," which wants precise numbers over a length-only
  visual comparison — same reasoning as the GC per-collector `Table`.
  Deadlock detection — an alert (not a chart/gauge/table shape at all):
  surfaced as a status callout when `findDeadlockedThreads()` returns
  non-empty, absent otherwise.

## Classes / Metaspace
- Used / committed / loaded / unloaded — [x] `MemoryPoolMXBean` / `ClassLoadingMXBean`
- History, 40-sample, separate used/committed — [x] same `Deque` pattern as Heap/CPU
- Per-class table (name, loader, instances, size) — feasibility still open,
  needs diagnostic-command MBeans, see open-questions.md — **not built**,
  the Classes screen ships without it rather than against placeholder data.
- **Display:** used/committed over time, auto-scaled Y-axis (see Display
  philosophy revision above) — this screen is its own detail view (not part
  of the 2x2 Overview grid), so it uses the full `Chart`, 2 LINE datasets,
  same as Memory's Heap chart. Per-class table — `Table` with filter/search,
  once the feasibility question above is resolved.

## VM Info / Host
- Label, JVM name+version, GC algorithm, arg count, classpath entries, uptime
  — [x]
- JIT total compilation time — [x] `CompilationMXBean.getTotalCompilationTime()`,
  guarded by `isCompilationTimeMonitoringSupported()`; bean itself is optional
  (not every JVM exposes one) and degrades to 0 rather than failing `start()`
- System load average — [x] `OperatingSystemMXBean.getSystemLoadAverage()`
- Physical memory total/free — [x] `getTotalMemorySize()` / `getFreeMemorySize()`
- Swap total/free — [x] `getTotalSwapSpaceSize()` / `getFreeSwapSpaceSize()`
- Open file descriptors, used/max — [x] `com.sun.management.UnixOperatingSystemMXBean`,
  Unix-only, blank/hidden elsewhere (same risk class as open-questions.md known
  risk #1). Proxied as its own bean (`unixOsBean`, separate from the plain
  `OperatingSystemMXBean` proxy) rather than an `instanceof` check on the
  latter — a JDK dynamic proxy only satisfies `instanceof` for interfaces it
  was actually built with, so `osBean instanceof UnixOperatingSystemMXBean` is
  always false regardless of platform.
- **Display:** open file descriptors (used/max) and swap (used/total) — each
  its own `LineGauge`: both are pure "how close to the ceiling" risk
  indicators per the Display philosophy, where the ratio matters more than
  the raw number. Everything else in this section (JVM name/version, GC
  algorithm, arg count, classpath entries, uptime, JIT compile time, system
  load average, physical memory) — plain text, single current values with
  no ceiling to read against.

## Explicit non-goals [-]
- Heap dump / object histogram analysis
- CPU/memory sampling profiler, call trees
- Flame graphs

Rationale: this app is a **monitor**, not a profiler. Conflicts with pillar 2
(lightweight) — VisualVM's headline features are exactly this, and that's a
desktop app with no footprint constraint.

## Design note: per-thread CPU time, poll-all vs poll-selected
For a ranked top-N-by-CPU table, all live threads must be measured every
tick — there's no way to know which are hottest without checking everyone
first. This rides on the same `getAllThreadIds()` call the state breakdown
already makes: one new bulk `getThreadCpuTime(long[])` call, no new
enumeration cost. A future "pin specific threads for a detail view" is a
separate, additive cost — `getThreadCpuTime(long)` for just the pinned IDs,
paid only when a user actually pins something. The two don't gate each other.

## Design note: GC notification listener belongs inside JmxPollingMetricsSource
Considered as a separate `MetricsSource` implementation, rejected:
`MetricsSource` is the abstraction for swapping the *entire* collection
mechanism (JMX polling vs a future JFR source), not for stacking a second
partial source alongside the first for the same connection. The notification
listener needs the same `MBeanServerConnection` and the same GC `ObjectName`s
the poll source already resolves in `start()` — a separate implementation
would either duplicate the connection (real resource cost) or thread a
shared connection between two independent implementations, which is coupling
with extra steps. It would also force merging two `MetricsSnapshot`s into
one on every render, reopening the multiple-simultaneous-connections
question in open-questions.md for no user-facing benefit. Resolution: one
more thing `JmxPollingMetricsSource` collects, same as `memoryBean`,
`gcBeans`, `threadBean` are already plain fields it wires up.

## Collection mechanism
JMX polling is the default (per architecture.md and requirements.md). JFR
event streaming stays parked. The GC notification-listener item above is a
separate, still-JMX mechanism question — not a JFR question — tracked in
open-questions.md.
