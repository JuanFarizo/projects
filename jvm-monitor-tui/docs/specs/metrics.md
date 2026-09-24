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
legend, more headroom) was originally reserved for the one-screen-per-metric
detail views (Memory, Classes/Metaspace, GC Log) on the assumption that more
room fixes what the 2x2 grid couldn't — **revised again after testing**:
`Chart`'s axis-title column is a fixed 1 character wide and wraps a 2-char
title ("MB") into a vertical "M"/"B" stack, and its LINE+BRAILLE
interpolation produces dense zigzag artifacts once ~40 history samples get
stretched across a full-width terminal — a rendering defect, not a room
problem, so giving it more space didn't help. Memory's Heap panel and
Classes/Metaspace's panel (see below) both moved to `DualSparkline` for this
reason, leaving GC Log as the only detail-screen `Chart` user still pending
the same check.
Also revised: Heap/CPU/Metaspace charts auto-scale their Y-axis to the
visible data window instead of pinning it to the ceiling (max heap / 100%).
Fixed-at-ceiling meant a lightly-loaded JVM's line sat static on the bottom
row — informative for "how close to the ceiling" but useless for seeing
actual movement, and movement is what these panels are for at a glance.
**Revised again — DualSparkline height:** `DualSparklineElement.preferredSize()`
hard-codes a 3-row height regardless of `availableHeight`, the same class of
defect already documented above for `BarChart` (which ignores `barGap`).
`.fill()` alone silently clips to that 3-row minimum whenever a container
falls back to querying `preferredSize()` — this is what left roughly half of
Memory's HEAP MEMORY panel visually blank (bars occupied a thin strip, the
rest of the `.fill()`-sized panel stayed empty). Fixed the same way as
BarChart: an explicit `.length(n)` on the sparkline element instead of
`.fill()`, sized to the content it actually needs, with the panel itself also
switched from open-ended `.fill()` to a matching explicit `.length()`. Applies
to both Memory screen sparklines (Heap, off-heap buffer trend).

Tried an explicit exception for Memory's Heap panel (`DualSparkline.max()`
pinned to `heap.max()`, on the theory that screen's whole purpose is the
precision/ceiling read) — reverted after testing: real heap max is
typically set far above real usage (e.g. 4096MB max vs. 30-50MB used),
which flattened the line to invisible, the exact failure this auto-scale
rule exists to avoid. No exception; Memory matches Overview. The direct
ceiling comparison is still available from the plain-text max/committed
numbers next to each chart.

## Heap
- Used / committed / max — [x] `MemoryMXBean.getHeapMemoryUsage()`
- Eden / Old / Survivor breakdown — [x] `MemoryPoolMXBean`, name-substring match
  (HotSpot-only — see open-questions.md known risk #2)
- History, 40-sample sparkline — [x], separate used/committed histories
- **Display:** used/committed over time — both Overview and Memory detail
  screen use `DualSparkline` (top=used, bottom=committed), `showYAxis(true)`,
  `xLabels("-40s","now")`, auto-scaled Y-axis (see Display philosophy
  revision above for why Memory dropped the full `Chart` it used to have
  here, and for why pinning it to `heap.max()` was tried and reverted).
  Eden/Old/Survivor — see Non-heap's combined `BarGroup` below.

## Non-heap
- Used / committed / max (aggregate) — [x] `MemoryMXBean.getNonHeapMemoryUsage()`.
  Max is shown in the Memory detail screen's stat row (previously collected,
  not displayed) — a real ceiling-risk number, not a new metric.
- Code Cache — [x] `MemoryPoolMXBean`, name-substring match. Since JDK 9 Code
  Cache is segmented into several `CodeHeap '...'` pools (non-nmethods/
  profiled/non-profiled), not one pool named "Code Cache" — matched and
  summed across all of them (same risk class as Eden/Old/Survivor matching).
- Code Cache max (aggregate ceiling) — [x] `MemoryPoolMXBean.getUsage().getMax()`,
  summed across the same segmented pools as Code Cache used. If any segment
  reports an undefined max (`< 0`), the aggregate is treated as "no ceiling"
  (`-1`) rather than silently understating it by summing a real number with
  an undefined one.
- Compressed Class Space — [x] `MemoryPoolMXBean`
- Metaspace — spec'd separately under Classes/Metaspace (below)
- **Display:** pool breakdown at a point in time (Eden/Old/Survivor + Code
  Cache/Compressed Class Space) — one `BarGroup`, one bar per pool via
  `Bar.of(value, label)` for exact-value labels. Categorical snapshot, no
  time dimension, so `Chart`/`Sparkline` don't apply here. Code Cache's
  used/max/ratio is additionally shown as a plain-text line below the chart
  (bold+red above 85% utilization) — it's the one non-heap pool with a real
  ceiling, so it earns the ratio-to-cap treatment the bar chart alone can't
  give it (a bar has no cap reference line).

## Off-heap buffers
- Direct buffer pool: count / used / capacity — [x]
  `BufferPoolMXBean` (`java.nio:type=BufferPool,name=direct`)
- Mapped buffer pool: count / used / capacity — [x] same bean, `name=mapped`
- Why: common leak source in NIO/Netty-style apps, invisible without this.
- Direct/mapped used history, 40-sample — [x] same bounded-`Deque` ring-buffer
  pattern as Heap/Classes, but in KB not MB: direct buffer usage is routinely
  well under 1MB on lightly-loaded targets, and MB-granularity history
  rounded that down to a permanently flat 0 (the "0.0MB" reading that looked
  like a bug but wasn't — see used/capacity display note below).
- `-XX:MaxDirectMemorySize` — [x] `com.sun.management.HotSpotDiagnosticMXBean.
  getVMOption("MaxDirectMemorySize")`, HotSpot-only (same risk class as the
  Unix-only file-descriptor gauge), cached once at `start()` like
  `vmStartTimeMillis` since it's a launch-time invariant, not a per-poll
  value. `0`/unsupported means "no explicit cap set" — the JVM still applies
  an effective default internally (`-Xmx`) but doesn't report that derived
  value back through this bean, so the UI shows "not set" rather than
  guessing at the effective number.
- **Display:** plain text (count/used/capacity per pool), now formatted with
  adaptive KB/MB instead of fixed MB (values under 1MB show as e.g. "312.0KB"
  instead of rounding to "0.0MB") — a display-precision fix, not new data.
  Direct-memory ceiling shown as its own used/limit/ratio line (bold+red
  above 85%) when `-XX:MaxDirectMemorySize` was explicitly set, otherwise "not
  set (JVM defaults to -Xmx)". Direct/mapped used history added as a
  `DualSparkline` (top=direct, bottom=mapped) below the text rows — trend
  visibility for the leak case this section's rationale already named;
  revisiting the "no trend widget yet" line above.

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
- **Display:** `Chart` with `GraphType.BAR` — one bar per GC event, x=time,
  y=pause ms. This is the metric the tail-latency argument was built on —
  averaging or a smoothed trend line would hide the very outlier this
  metric exists to surface, so one mark per individual event is the only
  shape that actually serves the purpose. Originally `GraphType.SCATTER`
  (floating dots); switched to `BAR` after testing — a dot has no baseline,
  so its height is hard to read against the axis at a glance. `BAR`
  ("renders vertical bars from the X-axis to each data point") anchors each
  event, matching the convention GCViewer's own pause-time chart uses (each
  pause as a bar from zero, height = duration). Same data, same two
  datasets (young/full), just anchored. Last-pause value on its own
  (duration/cause/generation, most recent) is a single event, not a series —
  plain text, not a widget.
- Heap reclaimed per pause — [x] `GcInfo.getMemoryUsageBeforeGc()` /
  `getMemoryUsageAfterGc()` (`Map<String, MemoryUsage>`, summed across pools),
  added to `GcPauseEvent` as `heapBeforeBytes`/`heapAfterBytes`. Same
  notification callback as duration/cause — no extra JMX round-trip.
- Pause percentiles (p50/p95/max) over the visible history — [x] computed
  from `GcSnapshot.pauseHistory()`, already-collected data, no new source.
- Full-GC ratio over the visible history — [x] `fullCount / pauseHistory.size()`;
  flagged (bold+red) above 25% (`FULL_GC_WARN_RATIO`), a share this high
  typically means heap pressure, not routine young GCs.
- Pause cause breakdown (count per distinct cause string) — [x] grouped from
  `pauseHistory`, already-collected data.
- Time since last GC / average interval between pauses — [x] derived from
  `pauseHistory` timestamps, already-collected data.
- Outlier-pause severity on the last pause — [x] the last pause's duration is
  flagged (bold+red) when it exceeds `1.5x` (`PAUSE_OUTLIER_MULTIPLIER`) its
  own collector's average pause (`GcCollectorStat.avgPauseMs()`). Deliberately
  relative to each collector's own history, not an absolute ms cutoff — no
  such fixed threshold existed anywhere in the codebase, and one would mean
  different things on different heap sizes.
- **Display, revised:** the pause-events `Chart` panel is now half-width
  (`.fill(2)` of a 2-part row) next to a new plain-text "PAUSE STATS" panel
  (percentiles, full-GC ratio, time-since-last/interval, cause breakdown) at
  the other half-width (`.fill(1)`) — the chart alone previously spanned the
  full row with a lot of visually empty space between sparse bars; the second
  panel puts that width to use instead of leaving it blank. Last-pause table
  gained a "Reclaimed" column (before-minus-after heap, formatted MB) and the
  duration cell is styled per the outlier-severity rule above.

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
- Metaspace max (ceiling) — [x] `metaspaceBean.getUsage().getMax()`, same bean
  already used for used/committed. `-1` ("no ceiling") is the common case —
  `-XX:MaxMetaspaceSize` is unset by default, unlike Heap/Code Cache which
  usually have a real cap.
- History, 40-sample, separate used/committed — [x] same `Deque` pattern as Heap/CPU
- Loaded-class delta history, 40-sample — [x] classes newly loaded per poll
  tick (`max(0, loaded - previousLoaded)`), not the raw loaded count: the raw
  count only trends slowly upward and would flatten a sparkline, while the
  delta spikes on dynamic-class-generation bursts (proxies, Groovy, bytecode
  frameworks) — the actual churn signal a monitor user wants.
- Per-class histogram (name, instances, bytes) — [x] `com.sun.management:type=DiagnosticCommand`
  MBean, `gcClassHistogram` operation. Corrects open-questions.md's original
  ObjectName guess (`DiagnosticCommandMBean`) — verified live against a real
  JDK 25 process: the actual ObjectName is `DiagnosticCommand`. The operation
  returns plain `java.lang.String` (a `jmap -histo`/`jcmd GC.class_histogram`-
  style text report), not a typed JMX open type, so it's parsed by a
  HotSpot-family-only `ClassHistogramParser`, wrapped in try/catch, degrading
  to an "unavailable" message on any other vendor/format rather than failing
  the screen. See open-questions.md's resolution note and known risk #8 on
  format stability.
- Loader column — [-] rejected for v1: no diagnostic command returns
  name+loader+instances+size together. Joining `gcClassHistogram` with a
  second command (`vmClassloaderStats`) by class-name string would double
  the parsing-fragility surface for a column that isn't core. Revisit only
  if a real need for it comes up.
- Per-class "details" — [-] rejected: not sourced from any metric, MXBean, or
  diagnostic command found during research; an undefined mockup element,
  dropped rather than invented.
- On-demand only, never polled — [x] `gcClassHistogram` walks the whole
  heap/metaspace (safepoint-inducing on the target JVM); running it every
  1000ms poll tick like the rest of `ClassesSnapshot` would itself become
  "noticeable load on the target" (pillar 3). Fetched once per explicit user
  refresh (key binding), outside `JmxPollingMetricsSource`'s poll loop.
- **Display:** Metaspace used/committed over time — `DualSparkline`, reversing
  this file's earlier Display-philosophy revision for this one panel: in
  practice the full-axis `Chart` wasn't adding a readable signal over the
  compact form, so it's demoted to the same treatment as Overview's Heap/CPU
  panels, just at full screen width. Same `preferredSize()`-under-reports /
  wrapping-`Column`-must-also-get-an-explicit-`.length()` fix as MemoryScreen's
  sparklines applies here too — both the metaspace and loaded-class-delta
  sparklines, and their wrapping `Column`, use explicit `.length()`.
  Metaspace used/max/ratio shown as its own text line (bold+red above 85%
  utilization), same treatment as MemoryScreen's Code Cache line — usually
  reads "no limit" since `-XX:MaxMetaspaceSize` is rarely set.
  Loaded-class-delta trend — plain `Sparkline` (single series, not `DualSparkline`
  — there's no paired second series here), labeled "new classes/tick" since an
  unlabeled delta chart reads as ambiguous.
  Loaded Classes — `Table`, rows = top N by `#bytes` descending (fixed sort;
  no interactive sort/filter/search for v1 — the constraint is the underlying
  data source per the histogram note above, not the widget; revisiting this for
  an alternate sort was considered and rejected again for the same reason).
  A summary line (class count / total instances / total bytes across every
  fetched entry, not just the displayed top N) sits above the table — the
  table alone only shows the biggest offenders, with no sense of the total.
  The panel title also shows "refreshed Ns ago" once a fetch has completed —
  histogram data is on-demand, never polled, so without this the user has no
  way to tell if what's on screen is fresh or from several refreshes ago.

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
