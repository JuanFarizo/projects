package org.a2aproject.sdk.examples.helloworld.client;

import static org.a2aproject.sdk.extras.opentelemetry.client.OpenTelemetryClientTransportWrapper.OTEL_TRACER_KEY;
import static org.a2aproject.sdk.extras.opentelemetry.client.propagation.OpenTelemetryClientPropagatorTransportWrapper.OTEL_OPEN_TELEMETRY_KEY;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.function.BiConsumer;
import java.util.function.Consumer;

import org.a2aproject.sdk.A2A;

import org.a2aproject.sdk.client.Client;
import org.a2aproject.sdk.client.ClientBuilder;
import org.a2aproject.sdk.client.ClientEvent;
import org.a2aproject.sdk.client.MessageEvent;
import org.a2aproject.sdk.client.TaskEvent;
import org.a2aproject.sdk.client.TaskUpdateEvent;
import org.a2aproject.sdk.client.http.A2ACardResolver;
import org.a2aproject.sdk.client.transport.grpc.GrpcTransport;
import org.a2aproject.sdk.client.transport.grpc.GrpcTransportConfigBuilder;
import org.a2aproject.sdk.client.transport.jsonrpc.JSONRPCTransport;
import org.a2aproject.sdk.client.transport.jsonrpc.JSONRPCTransportConfig;
import org.a2aproject.sdk.client.transport.rest.RestTransport;
import org.a2aproject.sdk.client.transport.rest.RestTransportConfig;
import org.a2aproject.sdk.client.transport.spi.ClientTransportConfig;
import org.a2aproject.sdk.jsonrpc.common.json.JsonUtil;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonParser;
import org.a2aproject.sdk.spec.AgentCard;
import org.a2aproject.sdk.spec.Artifact;
import org.a2aproject.sdk.spec.Message;
import org.a2aproject.sdk.spec.Part;
import org.a2aproject.sdk.spec.Task;
import org.a2aproject.sdk.spec.TaskArtifactUpdateEvent;
import org.a2aproject.sdk.spec.TextPart;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import io.grpc.Channel;
import io.grpc.ManagedChannelBuilder;
import io.opentelemetry.api.trace.propagation.W3CTraceContextPropagator;
import io.opentelemetry.context.propagation.ContextPropagators;
import io.opentelemetry.exporter.otlp.trace.OtlpGrpcSpanExporter;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.resources.Resource;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor;
import java.util.function.Function;

/**
 * A simple example of using the A2A Java SDK to communicate with an A2A server.
 * This example is equivalent to the Python example provided in the A2A Python SDK.
 */
public class HelloWorldClient {

    private static final Logger LOG = LoggerFactory.getLogger(HelloWorldClient.class);
    private static final com.google.gson.Gson PRETTY_JSON = new GsonBuilder().setPrettyPrinting().create();

    private static final String SERVER_URL = "http://localhost:9999";

    /** Re-formats already-serialized JSON for readable console output; the wire payload itself stays compact. */
    private static String pretty(String json) {
        return PRETTY_JSON.toJson(JsonParser.parseString(json));
    }
    private static final String MESSAGE_TEXT = "Customers cannot complete payments since 14:00.";

    public static void main(String[] args) {
        OpenTelemetrySdk openTelemetrySdk = null;
        try {
            AgentCard publicAgentCard = A2ACardResolver.builder().baseUrl(SERVER_URL).build().getAgentCard();
            LOG.info("Successfully fetched public agent card:");
            LOG.info("\n{}", pretty(JsonUtil.toJson(publicAgentCard)));
            LOG.info("Using public agent card for client initialization (default).");
            AgentCard finalAgentCard = publicAgentCard;

            if (publicAgentCard.capabilities().extendedAgentCard()) {
                LOG.info("Public card supports authenticated extended card. Attempting to fetch from: {}/ExtendedAgentCard", SERVER_URL);
                Map<String, String> authHeaders = new HashMap<>();
                authHeaders.put("Authorization", "Bearer dummy-token-for-extended-card");
                AgentCard extendedAgentCard = A2A.getAgentCard(SERVER_URL, "/ExtendedAgentCard", authHeaders);
                LOG.info("Successfully fetched authenticated extended agent card:");
                LOG.info("\n{}", pretty(JsonUtil.toJson(extendedAgentCard)));
                LOG.info("Using AUTHENTICATED EXTENDED agent card for client initialization.");
                finalAgentCard = extendedAgentCard;
            } else {
                LOG.info("Public card does not indicate support for an extended card. Using public card.");
            }

            final CompletableFuture<String> messageResponse = new CompletableFuture<>();

            // Create consumers list for handling client events
            List<BiConsumer<ClientEvent, AgentCard>> consumers = new ArrayList<>();
            consumers.add((event, agentCard) -> {
                // BREAKPOINT: step through submitted -> working -> artifact -> completed one event at a time
                try {
                    LOG.info("[wire]\n{}", pretty(JsonUtil.toJson(event)));
                } catch (Exception e) {
                    LOG.info("[wire]      (unable to serialize event: {})", e.getMessage());
                }

                if (event instanceof MessageEvent messageEvent) {
                    Message responseMessage = messageEvent.getMessage();
                    String text = extractText(responseMessage.parts());
                    LOG.info("[message]   {}", text);
                    messageResponse.complete(text);
                } else if (event instanceof TaskEvent taskEvent) {
                    var state = taskEvent.getTask().status().state();
                    LOG.info("[task]      {}", state);
                    if (state.isFinal()) {
                        messageResponse.complete(extractLastArtifactText(taskEvent.getTask()));
                    }
                } else if (event instanceof TaskUpdateEvent taskUpdateEvent) {
                    if (taskUpdateEvent.getUpdateEvent() instanceof TaskArtifactUpdateEvent artifactUpdate) {
                        String text = extractText(artifactUpdate.artifact() != null ? artifactUpdate.artifact().parts() : null);
                        LOG.info("[artifact]  {}", text);
                    } else {
                        var state = taskUpdateEvent.getTask().status().state();
                        LOG.info("[status]    {}", state);
                        if (state.isFinal()) {
                            messageResponse.complete(extractLastArtifactText(taskUpdateEvent.getTask()));
                        }
                    }
                } else {
                    LOG.info("Received client event: {}", event.getClass().getSimpleName());
                }
            });

            // Create error handler for streaming errors
            Consumer<Throwable> streamingErrorHandler = (error) -> {
                LOG.error("Streaming error occurred: {}", error.getMessage(), error);
                messageResponse.completeExceptionally(error);
            };

            if (Boolean.getBoolean("opentelemetry")) {
                openTelemetrySdk = initOpenTelemetry();
            }

            ClientBuilder clientBuilder = Client
                    .builder(finalAgentCard)
                    .addConsumers(consumers)
                    .streamingErrorHandler(streamingErrorHandler);
            configureTransport(clientBuilder, openTelemetrySdk);
             Client client = clientBuilder.build();

            // BREAKPOINT: inspect the fixed incident prompt right before it's sent
            Message message = A2A.toUserMessage(MESSAGE_TEXT); // the message ID will be automatically generated for you
            try {
                LOG.info("Sending message: {}", MESSAGE_TEXT);
                LOG.info("[wire]\n{}", pretty(JsonUtil.toJson(message)));
                client.sendMessage(message);
                LOG.info("Message sent successfully. Responses will be handled by the configured consumers.");

                String responseText = messageResponse.get();
                LOG.info("Response: {}", responseText);
            } catch (Exception e) {
                LOG.error("Failed to get response: {}", e.getMessage());
            }
        } catch (Exception e) {
            LOG.error("An error occurred: {}", e.getMessage(), e);
        } finally {
            // Ensure OpenTelemetry SDK is properly shut down to export all pending spans
            if (openTelemetrySdk != null) {
                LOG.info("Shutting down OpenTelemetry SDK...");
                openTelemetrySdk.close();
                LOG.info("OpenTelemetry SDK shutdown complete.");
            }
        }
    }

    static OpenTelemetrySdk initOpenTelemetry() {
        SdkTracerProvider sdkTracerProvider = SdkTracerProvider.builder()
                .addSpanProcessor(BatchSpanProcessor.builder(
                        OtlpGrpcSpanExporter.builder()
                                .setEndpoint("http://localhost:5317")
                                .build()
                ).build())
                .setResource(Resource.getDefault().toBuilder()
                        .put("service.version", "1.0")
                        .put("service.name", "helloworld-client")
                        .build())
                .build();

        return OpenTelemetrySdk.builder()
                .setTracerProvider(sdkTracerProvider)
                .setPropagators(ContextPropagators.create(W3CTraceContextPropagator.getInstance()))
                .build();
    }
    private static void configureTransport(ClientBuilder clientBuilder, OpenTelemetrySdk openTelemetrySdk) {
        ClientTransportConfig transportConfig;
        switch(System.getProperty("quarkus.agentcard.protocol", "JSONRPC")) {
            case "GRPC":
                Function<String, Channel> channelFactory = url -> {
                    // Extract "localhost:9999" from "http://localhost:9999"
                    String target = url.replaceAll("^https?://", "");
                    return ManagedChannelBuilder.forTarget(target)
                            .usePlaintext() // No TLS
                            .build();
                };
                transportConfig = new GrpcTransportConfigBuilder().channelFactory(channelFactory).build();
                updateTransportConfig(transportConfig, openTelemetrySdk);
                clientBuilder.withTransport(GrpcTransport.class, transportConfig);
                break;
            case "HTTP+JSON":
                transportConfig = new RestTransportConfig();
                updateTransportConfig(transportConfig, openTelemetrySdk);
                clientBuilder.withTransport(RestTransport.class, transportConfig);
                break;
            case "JSONRPC":
            default:
                transportConfig = new JSONRPCTransportConfig();
                updateTransportConfig(transportConfig, openTelemetrySdk);
                clientBuilder.withTransport(JSONRPCTransport.class, transportConfig);
                break;
        }
    }

    /** Extracts and concatenates the text of every {@link TextPart} in the given parts list. */
    private static String extractText(List<Part<?>> parts) {
        if (parts == null) {
            return "(no parts)";
        }
        StringBuilder textBuilder = new StringBuilder();
        for (Part<?> part : parts) {
            if (part instanceof TextPart textPart) {
                textBuilder.append(textPart.text());
            }
        }
        return textBuilder.toString();
    }

    /** Extracts the text of the most recently produced artifact on a task (the LLM's diagnosis). */
    private static String extractLastArtifactText(Task task) {
        List<Artifact> artifacts = task.artifacts();
        if (artifacts == null || artifacts.isEmpty()) {
            return "(no artifact)";
        }
        return extractText(artifacts.get(artifacts.size() - 1).parts());
    }

    private static void updateTransportConfig(ClientTransportConfig transportConfig, OpenTelemetrySdk openTelemetrySdk) {
        if (openTelemetrySdk != null) {
            Map<String, Object> parameters = new HashMap<>(transportConfig.getParameters());
            parameters.put(OTEL_TRACER_KEY, openTelemetrySdk.getTracer("helloworld-client"));
            parameters.put(OTEL_OPEN_TELEMETRY_KEY, openTelemetrySdk);
            transportConfig.setParameters(parameters);
        }
    }
}
