# Handoff: JVM Monitor TUI — Screen Mocks

## Overview
Mockups for a terminal-based JVM monitoring tool (a TUI analog to Java VisualVM), built for a Java 25 project using the **TamboUI** library (https://tamboui.dev/docs) to render the terminal interface. Screens covered: process/connection picker, add-remote-connection dialog, overview dashboard, and classes/metaspace browser.

## About the Design Files
The bundled file (`jvm-monitor-tui-mock.html`) is an **HTML/CSS design reference**, built to visualize layout, density, and information hierarchy — it is not code to port. It was built with box-drawing borders, monospace type, and flat colors to *simulate* a terminal, but it is a browser mockup, not a real terminal renderer.

**The actual implementation target is TamboUI, not HTML/CSS/DOM.** I (the design agent) do not have knowledge of TamboUI's actual API, widget set, or layout primitives beyond what's listed on its docs site (tables, charts, sparklines, lists). The developer implementing this should:
1. Consult the TamboUI docs (https://tamboui.dev/docs) for the real available widgets, borders, panel/box components, and styling API (does it support truecolor? per-cell styling? borders with title labels?).
2. Map each mock element below to the nearest TamboUI primitive — e.g. a "bordered panel with a label cut into the top border" may or may not be a built-in TamboUI component; if not, approximate with what TamboUI does offer.
3. Treat pixel measurements (padding, gaps) as **relative proportions**, not literal px — terminals are cell-based (rows/cols), so translate spacing into cell counts (e.g. "1 blank row above/below a table" rather than "16px").

## Fidelity
**Low-to-medium fidelity for a terminal context.** Colors, type hierarchy (via color/weight, since terminals don't have font families), and layout structure are intentional and should be preserved. Exact HTML pixel values (font-size: 14px, padding: 22px, etc.) do NOT carry over — they're an artifact of browser rendering and should be re-expressed in terminal cells/rows and TamboUI's own spacing model.

## Navigation model
Command-driven, no persistent nav chrome (no tab bar or sidebar). Screens are switched by key press. In the mock, a footer hint line shows the active keybindings per screen, and there's a small on-screen key legend for prototype clickability only — **the real app should have no mouse-click affordances**, it's keyboard-only.

Key bindings shown in mock (adjust freely — these are illustrative, not final):
- Connections screen: `↑↓` select, `enter` connect, `n` new remote connection, `r` refresh, `q` quit
- Add-remote dialog: `tab` next field, `space` toggle radio/checkbox, `enter` save, `esc` cancel
- Overview screen: `t` threads, `c` classes, `g` gc log, `esc` disconnect, `q` quit
- Classes screen: `/` search/filter, `s` sort by size, `enter` class details, `esc` back, `q` quit

## Screens

### 1. Connections (process picker)
**Purpose:** Entry screen. Pick a local JVM process to attach to, or a saved remote (JMX) connection.

**Layout:** Header bar (app name + version, right-aligned status text) with a bottom rule. Below it, two bordered sections stacked vertically, each with a label cut into the top border (`┌─ LOCAL PROCESSES ─┐` style): 
- **Local Processes** table: columns PID, Main Class, User, Heap, Uptime, Status. First/selected row is highlighted with a tinted row background and brighter text.
- **Saved Remote Connections** table: columns Host:Port, Alias, Last Connected, Status.

Status column uses a colored dot + label (`● RUNNING` in accent color, `○ IDLE`/`○ unreachable` in muted grey).

**Colors:** background `--color-bg` (#161826 equivalent), default text `--color-neutral-400` (~#b2b6ca), muted/secondary text `--color-neutral-600` (~#75798c), selected row text near-white (~#e9e9ed) on a faint accent-tinted background (`rgba(145,132,217,0.12)`), accent color `#d2cefd`/`#9184d9` family for section labels, status-good dots, and the app name.

**Sample content (placeholder data, replace with real):**
- Processes: PID 48213 `com.acme.orders.OrderServiceApplication` (running), PID 51890 `com.acme.billing.BillingWorker` (running), PID 39012 Gradle daemon (idle), PID 61234 `com.acme.gateway.GatewayApplication` (running)
- Remotes: `10.20.4.11:9010` (prod-orders-1, reachable), `10.20.4.12:9010` (prod-orders-2, reachable), `staging.internal:9010` (staging-gateway, unreachable)

### 2. Add Remote Connection (dialog)
**Purpose:** Form to register a new saved remote JMX connection.

**Layout:** Modal box centered over a dimmed connections screen (dim overlay ~72% opacity black). Box has an accent-colored border (distinguishes it as focused/active, vs neutral-grey borders elsewhere) and a label cut into the top border: "ADD REMOTE CONNECTION". Two-column label/field grid inside (label column ~120px equivalent, i.e. a fixed narrow gutter).

**Fields:**
- Alias (text input, shown with cursor)
- Host (text input)
- Port (text input)
- Protocol (radio: JMX (RMI) / JMX (JMXMP))
- Auth (radio: None / Username & Password)
- Username (text input, shown conditionally when Auth = Username/Password)
- Password (masked text input)
- SSL/TLS (checkbox: "use SSL/TLS for this connection")

Footer inside the dialog: left side shows active keys (`tab: next field  space: toggle  enter: save`), right side shows `esc: cancel`.

**Behavior notes for implementation:** Auth-dependent fields (username/password) should probably only render/enable when "Username / Password" is selected — the mock shows them always visible for reference; use judgment on whether TamboUI can conditionally show form rows.

### 3. Overview Dashboard
**Purpose:** Main live-monitoring screen after attaching to a JVM. Dense, at-a-glance expert view.

**Layout:** Header line: app main-class name (bold/bright), PID, JVM version string, uptime, status dot — all inline, wrapping if needed. Below: a 2×2 grid of bordered panels (label cut into top border, same convention as screen 1):
- **Heap Memory**: Used / Committed / Max as three inline stat pairs (label above value), a single-line sparkline (rendered here with block characters ▂▃▄▅▆▇█ in accent color), then a breakdown line (Eden / Old Gen / Survivor sizes).
- **CPU**: Process / System / Cores stats, a sparkline, and a rolling average line.
- **GC Activity**: a small table — Collector, Count, Total, Avg Pause — two sample rows (G1 Young Generation, G1 Old Generation).
- **Threads**: Live / Daemon / Peak / Started stats, then a line breaking down thread states (RUNNABLE, WAITING, TIMED_WAITING, BLOCKED) with counts.

Below the 2×2 grid, one full-width panel: **VM Info** — inline list of JVM version, GC algorithm, VM arg count, classpath entry count.

**Sparkline note:** mocked with Unicode block characters at 15px letter-spaced text — in TamboUI, use its real Sparkline widget (per the docs) instead of faking it with block-character text.

**Colors:** same palette as screen 1. Stat "label" text is small and very muted (`--color-neutral-600`), stat "value" text is either bright (primary stat) or `--color-neutral-300` (secondary stats in the same group).

### 4. Classes / Metaspace
**Purpose:** Browse loaded classes, inspect metaspace usage.

**Layout:** Top panel: **Metaspace** — Used / Committed / Loaded / Unloaded stat quad, then a sparkline. Below: a live filter/search line styled like a shell prompt (`/ order▌   14,982 classes · 6 matched`) — the accent-colored `▌` represents a text cursor. Below that, a bordered **Loaded Classes** table: Class Name, Loader, Instances, Size — sortable/filterable per the footer hint.

**Sample content:** classes like `com.acme.orders.domain.Order`, `java.util.HashMap$Node`, `java.lang.String`, with loader (app/bootstrap), instance counts, and retained size.

## Design Tokens (from the mock; re-derive for TamboUI's actual styling API)
- Background: `#161826` (near-black blue-grey)
- Primary text: `#e9e9ed` (bright, used sparingly — selected rows, key headings)
- Secondary text: `#b2b6ca`
- Muted/tertiary text: `#75798c`
- Accent: `#9184d9` base / `#d2cefd` lighter variant (section labels, status-good, active nav, sparklines, dialog border, cursor)
- Borders: subtle dark grey, close to `#2a2d3d`–`#33364a` range (Nocturne's `--color-neutral-800/900`)
- Font: monospace (JetBrains Mono in the mock) — in TamboUI everything is monospace by nature of the terminal grid, so no action needed beyond confirming truecolor support
- Panel convention: 1px border box with a small label "cut into" the top border line, left-aligned, ~14px inset from the left edge — in a real terminal this is typically drawn by overlaying label text directly onto the top border character run

## Assets
None (no icons/images — pure text/box-drawing, consistent with a TUI).

## Files
- `jvm-monitor-tui-mock.html` — the interactive mock (open in a browser; press 1/2/3/n or click the small key legend at the bottom to switch screens)
- `screenshots/01-connections.png` — Connections/process picker
- `screenshots/02-add-remote.png` — Add Remote Connection dialog
- `screenshots/03-overview.png` — Overview dashboard
- `screenshots/04-classes.png` — Classes / Metaspace
