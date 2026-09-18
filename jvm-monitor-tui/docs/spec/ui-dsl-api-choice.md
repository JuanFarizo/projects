# TUI Framework

## Decision
Use `dev.tamboui.toolkit.app.ToolkitApp` (high-level, retained-mode toolkit), not the low-level `Backend`/`Terminal`/`Frame` API.

## Why
- App has multiple screens and key-driven navigation between them. `ToolkitApp` gives built-in event dispatch (`onKeyEvent`) and screen/focus management instead of a hand-rolled read loop.
- `render()` returns a declarative `Element` tree (`column`, `row`, `panel`, `text`, ...). Easier to compose and maintain than manual `Frame` drawing calls.
- Framework owns `Backend` setup, raw mode, resize handling, and redraw scheduling — removes boilerplate a manual event loop would need.

## Alternative considered
Low-level `Backend` + `Terminal<Backend>` + manual `Frame` rendering (immediate-mode). Rejected: fine for a single static screen, but requires manually managing the event loop, redraws, and key routing — overhead not justified for a multi-screen app.
