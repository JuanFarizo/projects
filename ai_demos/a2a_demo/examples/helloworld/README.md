# Incident Diagnostics Agent — A2A Live Demo

A minimal, live-demo-ready pair of programs showing the **real** A2A protocol on the
wire: discovery via `AgentCard`, a real `Task` lifecycle, real JSON-RPC messages, and a
server-backed LLM (via Ollama Cloud) actually reasoning about an incident report instead
of returning canned text.

This is a modified copy of the official `a2a-java` SDK's `examples/helloworld`
(`https://github.com/a2aproject/a2a-java`) — minimal diff on top of what already works:
renamed `AgentCard`/skill, a real Ollama Cloud call replacing the canned "Hello World"
response, and request/response logging so the wire protocol is visible on a projector.

## 7.1 Local setup

Prerequisites: Java 21+, Maven. (JBang is **not** needed — the client runs via
`mvn exec:java`, see below.)

1. This demo lives at `examples/helloworld/` in this repo, copied from
   `a2a-java/examples/helloworld` in the upstream SDK clone.
2. Build and install the A2A Java SDK into your local Maven repo (one-time, from the
   upstream SDK clone, not from this repo):
   ```bash
   cd /path/to/a2a-java
   mvn clean install -DskipTests
   ```
3. Get an Ollama Cloud API key at
   [ollama.com/settings/keys](https://ollama.com/settings/keys), then export it as
   `OLLAMA_API_KEY` (exact name matters — the code reads this specific variable):
   ```bash
   export OLLAMA_API_KEY="<your key>"
   ```
4. Start the server:
   ```bash
   cd examples/helloworld/server
   mvn quarkus:dev
   ```
   It listens on port `9999`. A successful startup ends with a line like:
   ```
   INFO  [io.quarkus] a2a-java-sdk-examples-server 1.3.1.Final-SNAPSHOT on JVM (powered by Quarkus 3.39.1) started in 1.7s. Listening on: http://localhost:9999
   INFO  [io.quarkus] Profile dev activated. Live Coding activated.
   ```
5. In a second terminal, run the client:
   ```bash
   cd examples/helloworld/client
   mvn exec:java
   ```

## 7.2 How to verify it's working

Quick smoke test, independent of the live demo:

```bash
curl http://localhost:9999/.well-known/agent-card.json
```
A healthy response is `200 OK` with JSON containing `"name":"Incident Diagnostics Agent"`
and a skill with `"id":"analyze-incident"`, and `"capabilities":{"streaming":true,...}`.

A full successful client run prints, in order (exact LLM wording varies, shape doesn't):
```
Successfully fetched public agent card: {...}
Sending message: Customers cannot complete payments since 14:00.
[wire]      {"role":"ROLE_USER","parts":[{"text":"..."}],...}
[status]    TASK_STATE_SUBMITTED
[status]    TASK_STATE_WORKING
[artifact]  <the LLM's diagnosis text>
[status]    TASK_STATE_COMPLETED
Response: <the LLM's diagnosis text>
```

Telling a real `failed` Task apart from a hung request (there is intentionally no
fallback/timeout, see §3.2.4): a hung request just sits there with no new `[wire]`/
`[status]` lines for many seconds; a real failure prints
`Streaming error occurred: ...` followed by a stack trace and
`Failed to get response: org.a2aproject.sdk.spec.InternalError: Agent execution failed: ...`
with the real underlying cause (e.g. an Ollama HTTP status and body) in the message —
nothing is swallowed.

## 7.3 Debugging the demo live (breakpoints)

Every location below already has a `// BREAKPOINT: <why>` comment in the source. Set
these before walking on stage, in the order a single client run naturally hits them:

1. **Client — `HelloWorldClient.main(...)`, line building/sending the `Message`**
   (`examples/helloworld/client/.../HelloWorldClient.java:137`, right at
   `A2A.toUserMessage(MESSAGE_TEXT)`): inspect the fixed incident prompt right before
   it's sent.
2. **Server — `RequestResponseLoggingRoutes.setupLogging(...)` request-log line**
   (`examples/helloworld/server/.../RequestResponseLoggingRoutes.java:29`): pause on the
   raw JSON-RPC envelope for both the discovery `GET` and the `message/stream` `POST`.
3. **Server — `AgentExecutorProducer`'s `execute(...)`, first line**
   (`examples/helloworld/server/.../AgentExecutorProducer.java:46`, at
   `context.getUserInput()`): inspect the incoming `RequestContext`/`Message` text as it
   arrives from the client, before anything else happens.
4. **Server — `AgentExecutorProducer.diagnoseIncident(...)`, request-body build line**
   (`AgentExecutorProducer.java:68`): inspect the exact prompt (system + user messages)
   being sent to Ollama before it goes out over the network.
5. **Server — `AgentExecutorProducer.diagnoseIncident(...)`, response-parse line**
   (`AgentExecutorProducer.java:89`): inspect the raw JSON response from Ollama and the
   extracted `choices[0].message.content`, right after the network call returns.
6. **Server — the `AgentEmitter` state transitions in `execute(...)`**
   (`AgentExecutorProducer.java:50` for `startWork()`, `:56` for `complete()`): step
   through the state machine live, one breakpoint per transition.
7. **Server — `RequestResponseLoggingRoutes.setupLogging(...)` response-log line**
   (`RequestResponseLoggingRoutes.java:40`, inside the `addBodyEndHandler`): pause on the
   response side of the same request/response pair.
8. **Client — the streaming event consumer, first line**
   (`HelloWorldClient.java:85`): step through
   `submitted → working → artifact → completed` one event at a time.

Note: the SDK's A2A endpoints (`POST /`, `GET /.well-known/agent-card.json`) are
registered directly on a Vert.x `Router` (see `A2AServerRoutes` in the SDK's
`a2a-java-sdk-reference-jsonrpc` module) rather than as JAX-RS resources — that's why the
logging hook here is a `Router`-level handler (`RequestResponseLoggingRoutes`), not a
JAX-RS `@Provider` filter (which would never fire for these routes).

## 7.4 Troubleshooting

- **`Failed to get response: ... HTTP 401: Unauthorized`** — `OLLAMA_API_KEY` isn't set,
  is empty, or was exported under a different name (must be exactly `OLLAMA_API_KEY`,
  not e.g. `OLLAMA_CLOUD_API_KEY`) in the same terminal *before* `mvn quarkus:dev` was
  started. Environment variables are read once at JVM start — export it, then restart
  the server (Quarkus dev-mode live reload does not re-read process environment
  variables).
- **`mvn quarkus:dev` fails to bind / "Address already in use"** — port `9999` (or `9000`
  for gRPC) is already taken by a previous run. Find and stop it
  (`lsof -i :9999`) or kill the old `quarkus:dev` process.
- **Venue wifi/network down** — the Ollama Cloud call will fail with a network exception
  (not an HTTP 401), surfaced the same way: `Streaming error occurred: ...` on the
  client and the real `IOException` message on the server console. There is no offline
  fallback by design (§3.2.4) — this is expected, not a bug, if the network is actually
  down.
