# JFR Evaluation

Status: **to evaluate** — no decision yet. Tracks the open question of whether JFR (Java Flight Recorder) event streaming should supplement JMX polling for metrics that polling cannot give. Follows the "only add it if polling demonstrably misses events" rule in [requirements.md](requirements.md); this doc defines how that is demonstrated.

## Goal
Decide, with evidence, whether JFR is worth adding for three areas:

| Area | What JMX polling gives today | What JFR could add (candidate events) |
|------|------------------------------|----------------------------------------|
| JIT | Total compilation time only | When and what is compiled/deoptimized: `jdk.Compilation`, `jdk.Deoptimization`, `jdk.CompilerInlining`, `jdk.CodeCacheFull` |
| GC | Per-collector count/total time/avg pause; last pause + cause via `GarbageCollectionNotificationInfo` | Every pause, phase breakdown, cause, heap before/after: `jdk.GarbageCollection`, `jdk.GCPhasePause`, `jdk.GCHeapSummary` |
| Memory allocation | Heap/pool usage only (no allocation rate, no allocation source) | Allocation rate and hot allocation sites/classes: `jdk.ObjectAllocationSample`, `jdk.ObjectAllocationInNewTLAB`, `jdk.ObjectAllocationOutsideTLAB` |

## Questions the evaluation must answer
1. **Gap vs polling.** For each area, which UI-useful data does JFR provide that JMX polling plus the existing GC notification listener cannot? Short GC pauses between poll ticks are the known example. If the answer is "nothing the UI needs", reject and record it.
2. **Overhead on the target JVM (pillar 3).** Measure the cost of the minimal event set (not the `profile` preset) on a loaded JVM. Streaming must stay at or below the cost of the current poll loop to be acceptable.
3. **Connection method coverage.** `RecordingStream` is local-only. Check whether `RemoteRecordingStream` (JMX, `jdk.management.jfr`) covers connection methods 2–4, and confirm methods 5 (SSH + jcmd/jstat) and 6 (Docker) cannot stream. Any partial coverage needs the same "accepted gap" treatment GC last-pause already has.
4. **Pillar 2 impact.** Dependencies on `jdk.jfr` / `jdk.management.jfr` modules, and whether JFR streaming works in the GraalVM native image of the monitor itself. Unresearched, treat as a blocker until verified (same risk class as the native-image items in [open-questions.md](open-questions.md)).
5. **Scope vs non-goals.** [requirements.md](requirements.md) rejects a "CPU/memory sampling profiler". Allocation events sit close to that line. Decide the boundary up front: aggregate allocation rate (likely in scope) vs per-class/per-site allocation tables (likely out of scope, needs an explicit requirements change).
6. **Architecture fit.** Confirm a JFR source fits behind the existing `MetricsSource` abstraction ([architecture.md](architecture.md), Metrics Layer) without UI changes, or whether it must be an additive source merged with polling. The [design note in metrics.md](metrics.md) rejected stacking a second partial source for GC; re-check that reasoning for JFR.

## Method
- Build a throwaway spike (not in `src/main`), run against a JVM with a known GC-heavy and allocation-heavy workload.
- Compare against the current JMX-polling output for the same period.
- Record numbers (events seen vs missed, overhead) in this doc.

## Outcome
Each area ends as one of: **adopt** (add to [metrics.md](metrics.md) as approved, update [architecture.md](architecture.md) and [requirements.md](requirements.md)), **reject** (record why in metrics.md), or **park** (record what would change the answer). Until then JMX polling remains the only mechanism.
