# Incident Diagnostics Client

A minimal, deterministic A2A client used for a live demo. It sends one fixed
incident-report prompt to the "Incident Diagnostics Agent" server
(`../server`) and prints the streamed `Task` lifecycle
(`submitted -> working -> artifact -> completed`) to the console as it
arrives.

## Prerequisites

- Java 21+
- Maven
- The server from `../server` running first (see its README) — this client
  no longer talks to a Python server; the server in this same demo is the
  A2A Java "Incident Diagnostics Agent".

## Build the A2A Java SDK

```bash
cd /path/to/a2a-java
mvn clean install
```

## Run the client

```bash
cd examples/helloworld/client
mvn exec:java
```

### Transport protocol selection

```bash
mvn exec:java -Dquarkus.agentcard.protocol=GRPC
mvn exec:java -Dquarkus.agentcard.protocol=HTTP+JSON
```

Default is `JSONRPC`. The protocol selected here must match the server's.

### Enabling OpenTelemetry (optional)

```bash
mvn exec:java -Dopentelemetry=true
```

## What the client does

1. Fetches the server's public (and, if supported, extended) agent card.
2. Sends the fixed prompt `"Customers cannot complete payments since 14:00."`
   as a streaming `message/stream` request.
3. Prints each streamed event as it arrives:
   ```
   [task]      TASK_STATE_SUBMITTED
   [status]    TASK_STATE_WORKING
   [artifact]  <the LLM's diagnosis text>
   [status]    TASK_STATE_COMPLETED
   ```
   Each event's raw payload is also printed, prefixed `[wire]`, so the
   JSON-RPC traffic is visible on the console without any extra tooling.
4. Prints the final response text once the task reaches a terminal state.

The client does not call any LLM itself and does not change the prompt at
runtime — it is a scripted caller, by design, for the live demo.
