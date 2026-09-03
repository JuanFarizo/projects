# Incident Diagnostics Server

An A2A server (Java + Quarkus) that investigates a production-incident description and
returns a real, LLM-generated root cause and next step (via Ollama Cloud), streamed
through a full `submitted → working → completed` `Task` lifecycle.

See the [demo root README](../README.md) for the full setup, verification, breakpoint,
and troubleshooting guide. Quick start:

```bash
cd examples/helloworld/server
export OLLAMA_API_KEY="<key from ollama.com/settings/keys>"
mvn quarkus:dev
```

Listens on `http://localhost:9999` by default.

### Transport Protocol Selection

The server supports multiple transport protocols via `quarkus.agentcard.protocol`:

```bash
mvn quarkus:dev                                        # JSONRPC (default)
mvn quarkus:dev -Dquarkus.agentcard.protocol=GRPC
mvn quarkus:dev -Dquarkus.agentcard.protocol=HTTP+JSON
```

## Notes

- Modify the agent's behavior in `AgentExecutorProducer.java`.
- Modify the agent card / skill metadata in `AgentCardProducer.java`.
- Request/response logging is in `RequestResponseLoggingRoutes.java` (a Vert.x `Router`
  handler, not a JAX-RS filter — see the root README's breakpoint section for why).
