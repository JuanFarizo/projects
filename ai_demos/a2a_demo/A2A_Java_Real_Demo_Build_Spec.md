# Build Spec: Real A2A Protocol Demo (Java, based on official `a2a-java` examples)

## 1. Objective

Modify the **official** A2A Java SDK examples — not a from-scratch build — into a small,
live-demo-ready pair of programs that show the **real** A2A protocol on the wire:
discovery via `AgentCard`, a real `Task` lifecycle, real JSON-RPC messages, and a
Server-backed LLM (via Ollama Cloud) actually reasoning about the request instead of
returning canned text.

**Audience:** senior Java developers, live 10-minute demo inside a 30-minute talk on A2A.
**Priority:** minimal diff on top of the official examples. Do not rewrite what already
works — add logging and swap the canned response for a real LLM call, and stop there.

## 2. Starting point — clone and use as-is where possible

Repository: `https://github.com/a2aproject/a2a-java`

Two subfolders are the base for this work:

- `examples/helloworld/server` — Java + Quarkus A2A server. **This is the one we modify
  the most** (AgentCard content + AgentExecutor logic + logging).
- `examples/helloworld/client` — Java + JBang A2A client. **Minimal changes only**
  (the prompt text + a bit of console output formatting for readability on a projector).

Do not restructure packages, do not change the build tooling (Quarkus for the server,
JBang for the client) — the goal is a small, reviewable diff against upstream, not a new
project.

---

## 3. Server changes (`examples/helloworld/server`)

### 3.1 AgentCard — rename to fit the incident-response story

Find the existing `AgentCard` producer (CDI `@Produces @PublicAgentCard`) and update it,
keeping the same builder shape already used in the example:

- `name`: `"Incident Diagnostics Agent"`
- `description`: `"Investigates production incidents and suggests a root cause"`
- Replace the single `hello_world` skill with:
  - `id`: `"analyze-incident"`
  - `name`: `"Analyze incident"`
  - `description`: `"Given a description of a production incident, investigates and
    proposes a likely root cause and next steps"`
  - `tags`: `["incident", "diagnostics"]`
  - `examples`: `["Customers cannot complete payments since 14:00"]`
- `capabilities`: set `streaming(true)` (needed for §3.4). Leave `pushNotifications` as
  in the original example (`false` is fine — out of scope for this demo).
- Leave `url`, `version`, `protocolVersion`, and CDI wiring untouched.

Do not add authentication/security schemes — keep the demo unauthenticated, matching the
original example, to avoid adding moving parts to a live demo.

### 3.2 AgentExecutor — replace the canned response with a real Ollama Cloud call

Find the existing `AgentExecutor` implementation (the class whose `execute(RequestContext,
EventQueue)` currently just emits a hardcoded "Hello World" text message) and replace its
body so that it:

1. Reads the incoming user text from `RequestContext` (the text `Part` of the last
   `Message`).
2. Calls **Ollama Cloud's OpenAI-compatible chat completions endpoint**:
   - `POST https://ollama.com/v1/chat/completions`
   - Header: `Authorization: Bearer ${OLLAMA_API_KEY}` (read from an environment
     variable — never hardcode the key).
   - Header: `Content-Type: application/json`
   - Body:
     ```json
     {
       "model": "gpt-oss:20b",
       "messages": [
         { "role": "system", "content": "You are an SRE agent. Given a short incident description, respond with a plausible root cause and one concrete next step, in 3-4 sentences, plain text, no markdown." },
         { "role": "user", "content": "<the incoming message text>" }
       ]
     }
     ```
   - Use plain `java.net.http.HttpClient` (already available in the JDK — no new HTTP
     dependency needed). Parse the JSON response with Jackson (already a transitive
     dependency via the A2A SDK) and extract `choices[0].message.content`.
   - **Model note for the implementing agent:** `gpt-oss:20b` is expected to be on
     Ollama's free cloud tier at the time this spec was written, but Ollama's free-tier
     model list changes. Before finalizing, check the current free tier at
     `ollama.com/settings/keys` (or the account's model catalog) and swap the model
     string if `gpt-oss:20b` is no longer free — any small/free chat-capable model works
     equally well for this demo.
3. Wraps the model's text response as the `Task`'s result: use the existing helper
   pattern already present in the example (`TaskUpdater` / `EventQueue`) to transition
   the task `submitted → working → completed` and attach the LLM's text as an
   `Artifact` (not as a `Message` — keep the Message/Artifact distinction we discussed:
   Artifact carries the actual result).
4. **No fallback, no retry, no timeout-and-continue.** If the HTTP call to Ollama Cloud
   fails (network error, non-200 response, malformed JSON), let the exception propagate
   so the `Task` ends in `failed` state with the real error surfaced — this is
   intentional for the talk; do not add a safety net or a canned backup response.

### 3.3 Environment variable

Document (in the server's `README.md`, one line) that `OLLAMA_API_KEY` must be exported
before starting the server:

```bash
export OLLAMA_API_KEY="<key from ollama.com/settings/keys>"
```

Do not read the key from a config file or commit it anywhere.

### 3.4 Streaming — use it so Task state transitions are visible live

The Ollama Cloud call takes a couple of seconds. Make sure the server path exercises
`message/stream` (not only the blocking `message/send`), so that during the live demo the
audience can see, in order:

```
Task (submitted)
TaskStatusUpdateEvent (working)
TaskArtifactUpdateEvent (the LLM's diagnosis)
TaskStatusUpdateEvent (completed)
```

Reuse whatever streaming support already exists in the example's `AgentExecutor` /
`EventQueue` wiring — do not build custom SSE handling from scratch.

### 3.5 Logging — make the wire protocol visible in the console

Add a small logging filter (a handful of lines, no new dependencies) so that when the
server runs (`mvn quarkus:dev`), the console prints, for every request:

```java
@ServerRequestFilter
public void logRequest(ContainerRequestContext ctx) {
    LOG.info(">>> {} {}", ctx.getMethod(), ctx.getUriInfo().getPath());
    // also log the request body for POST /a2a (the JSON-RPC envelope)
}

@ServerResponseFilter
public void logResponse(ContainerResponseContext ctx) {
    LOG.info("<<< {} {}", ctx.getStatus(), ctx.getEntity());
}
```

This should make the following visible live, without any extra tooling (no Postman, no
`curl`, no browser dev tools needed during the talk):

- The `GET /.well-known/agent-card.json` discovery request and the AgentCard JSON
  returned.
- The `POST` with the JSON-RPC `message/stream` (or `message/send`) envelope.
- The streamed `TaskStatusUpdateEvent` / `TaskArtifactUpdateEvent` payloads.

Use Quarkus's built-in `@ServerRequestFilter` / `@ServerResponseFilter` (Quarkus REST
declarative filters) — no manual `@Provider` boilerplate needed. Keep log format simple
(one line per event, indented JSON body is fine) — this is for a laptop terminal on a
projector, not a production log pipeline.

---

## 4. Client changes (`examples/helloworld/client`)

Minimal changes only:

1. Replace the hardcoded "Hello World" prompt with the incident description used
   throughout the talk: `"Customers cannot complete payments since 14:00."`
2. After receiving the streamed events, print each one to the console with a short
   label, so the flow is readable live, e.g.:
   ```
   [task]      submitted
   [status]    working
   [artifact]  <the LLM's diagnosis text>
   [status]    completed
   ```
3. **Enable the same client-side request/response logging via configuration only** (no
   code) in the client's `application.properties` (or equivalent config used by the
   JBang script):
   ```properties
   quarkus.rest-client.logging.scope=request-response
   quarkus.log.category."org.jboss.resteasy.reactive.client.logging".level=DEBUG
   ```
   If the JBang client does not use Quarkus's REST client (check the existing example
   first — it may use the SDK's own HTTP client instead), skip this and instead add one
   `System.out.println` right before sending the message that prints the outgoing
   JSON-RPC payload, and one right after receiving each streamed event that prints the
   raw payload. Keep it to plain `println` — no logging framework needed on the client
   side for a two-call demo.
4. Do **not** add any LLM call on the client side. The client stays a deterministic,
   scripted caller with a fixed prompt — this is intentional, not a placeholder to fill
   in later.

---

## 5. Explicitly out of scope

- No fallback/retry logic for the Ollama Cloud call (§3.2.4) — this is intentional.
- No authentication/security schemes on the AgentCard.
- No push notifications (webhook) flow — only discovery, streaming `message/stream`, and
  the resulting `Task`/`Artifact`.
- No multi-agent orchestration (no second/third specialist agent) — this demo is a
  single Client ↔ single Server exchange, on purpose, to keep the live demo simple and
  focused on protocol mechanics rather than a multi-agent story.
- No changes to the Maven/JBang build setup beyond what's needed to add the HTTP call to
  Ollama and the logging filters.

## 6. Run instructions (document these in each folder's README, don't change them)

```bash
# Server
cd examples/helloworld/server
export OLLAMA_API_KEY="<key>"
mvn quarkus:dev

# Client (separate terminal)
cd examples/helloworld/client
jbang HelloWorldClient.java
```

## 7. README (write one, at the repo root of this demo)

Write a single `README.md` — do not scatter instructions across multiple files. It must
have these sections, in this order:

### 7.1 "Local setup"

Step-by-step, copy-pasteable, assuming a clean machine with Java 21+, Maven, and
[JBang](https://www.jbang.dev/) installed:

1. Clone / where this code lives relative to the upstream `a2a-java` repo.
2. Export `OLLAMA_API_KEY` (link to `ollama.com/settings/keys` to get one).
3. Start the server: exact command (`mvn quarkus:dev` from the server folder), the port
   it listens on, and what a successful startup log line looks like (so the presenter
   knows it's ready without guessing).
4. Run the client: exact command (`jbang HelloWorldClient.java` from the client folder).

### 7.2 "How to verify it's working" (a quick smoke test, independent of the live demo)

- One `curl` command to hit `GET http://localhost:<port>/.well-known/agent-card.json`
  and a note on what a healthy response looks like (status 200, JSON with the
  `analyze-incident` skill).
- What a full successful client run looks like end-to-end in the console (expected
  output shape, not the exact LLM text since that varies).
- One line on how to tell a `failed` Task apart from a hung request (given there's no
  fallback/timeout by design — see §3.2.4), so the presenter can recognize a real
  Ollama/network problem versus the demo just being slow.

### 7.3 "Debugging the demo live (breakpoints)"

This is the most important section for the talk. List concrete breakpoint locations —
file name + method name (and a one-line reason to stop there) — that let the presenter
step through the whole request lifecycle live, in the order they'd naturally hit during
one client run. At minimum, include a breakpoint at:

- **Server — `AgentExecutor.execute(...)`, first line**: inspect the incoming
  `RequestContext` / `Message` text as it arrives from the client, before anything else
  happens.
- **Server — the line building the Ollama HTTP request body**: inspect the exact prompt
  being sent (system + user messages) before it goes out over the network.
- **Server — the line parsing the Ollama HTTP response**: inspect the raw JSON response
  and the extracted `choices[0].message.content`, right after the network call returns.
- **Server — the `TaskUpdater` call(s) that transition task state**: one breakpoint per
  transition (`working`, `completed`) so the presenter can step through the state
  machine from the earlier diagrams live, not just talk about it in the abstract.
- **Server — `logRequest` / `logResponse` filter methods**: to pause on the raw
  JSON-RPC envelope for both the discovery `GET` and the `message/stream` `POST`.
- **Client — the line building/sending the outgoing `Message`**: inspect the fixed
  incident prompt right before it's sent.
- **Client — the streaming event handler / loop**: one breakpoint inside the loop that
  processes each incoming event, so the presenter can step through
  `submitted → working → artifact → completed` one event at a time.

For each entry, give the exact class name and method/line description (not just "in the
executor somewhere") — the presenter needs to set these breakpoints in their IDE before
walking on stage, without having to search the codebase live. Prefer marking these
locations with a short `// BREAKPOINT: <why>` comment directly in the source in addition
to listing them in the README, so they're impossible to miss when opening the files.

### 7.4 "Troubleshooting"

Short list of the 2-3 most likely failure modes for a live demo (e.g. `OLLAMA_API_KEY`
not exported, port already in use, venue wifi down) and the one-line fix for each.

## 8. Acceptance checklist

- [ ] `mvn quarkus:dev` starts the server with no changes to how the original example is
      launched.
- [ ] `GET http://localhost:<port>/.well-known/agent-card.json` returns the updated
      AgentCard with the `analyze-incident` skill and `streaming: true`.
- [ ] Running the JBang client sends the fixed incident prompt and prints the streamed
      `Task` state transitions and the final `Artifact` text (a real, non-canned LLM
      response) to the console.
- [ ] The server console shows the discovery request, the JSON-RPC request, and each
      streamed event as it happens.
- [ ] Killing network access / unsetting `OLLAMA_API_KEY` and re-running causes the
      `Task` to end in `failed` with the real underlying error visible in both the
      server console and the client output — no silent fallback, no swallowed exception.
- [ ] No dependency was added beyond what's needed for the HTTP call to Ollama (plain
      `java.net.http.HttpClient` + existing Jackson) and the Quarkus logging filters.
- [ ] A single `README.md` exists with the four sections from §7 (Local setup, How to
      verify it's working, Debugging the demo live, Troubleshooting), and every command
      in it was actually run once to confirm it works as written.
- [ ] Every breakpoint location listed in §7.3 has a matching `// BREAKPOINT: <why>`
      comment in the actual source line, and the README references the same class/method
      names used in the code (no drift between the two).
