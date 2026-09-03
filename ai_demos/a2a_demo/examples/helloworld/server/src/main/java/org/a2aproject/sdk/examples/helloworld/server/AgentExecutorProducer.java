package org.a2aproject.sdk.examples.helloworld.server;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.List;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;

import org.a2aproject.sdk.server.agentexecution.AgentExecutor;
import org.a2aproject.sdk.server.agentexecution.RequestContext;
import org.a2aproject.sdk.server.tasks.AgentEmitter;
import org.a2aproject.sdk.spec.A2AError;
import org.a2aproject.sdk.spec.Part;
import org.a2aproject.sdk.spec.TextPart;
import org.a2aproject.sdk.spec.UnsupportedOperationError;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@ApplicationScoped
public class AgentExecutorProducer {

    private static final Logger LOGGER = LoggerFactory.getLogger(AgentExecutorProducer.class);

    private static final String OLLAMA_CHAT_COMPLETIONS_URL = "https://ollama.com/v1/chat/completions";
    private static final String OLLAMA_MODEL = "gpt-oss:20b";
    private static final String SYSTEM_PROMPT =
            "You are an SRE agent. Given a short incident description, respond with a "
            + "plausible root cause and one concrete next step, in 3-4 sentences, plain "
            + "text, no markdown.";

    private static final HttpClient HTTP_CLIENT = HttpClient.newHttpClient();

    @Produces
    public AgentExecutor agentExecutor() {
        return new AgentExecutor() {
            @Override
            public void execute(RequestContext context, AgentEmitter emitter) throws A2AError {
                // BREAKPOINT: inspect incoming RequestContext/Message text before anything else happens
                String incidentText = context.getUserInput();

                emitter.submit();
                // BREAKPOINT: step through the state machine live (submitted -> working)
                emitter.startWork();

                String diagnosis = diagnoseIncident(incidentText);

                emitter.addArtifact(List.of(new TextPart(diagnosis)));
                // BREAKPOINT: step through the state machine live (working -> completed)
                emitter.complete();
            }

            @Override
            public void cancel(RequestContext context, AgentEmitter emitter) throws A2AError {
                throw new UnsupportedOperationError();
            }
        };
    }

    private String diagnoseIncident(String incidentText) {
        // BREAKPOINT: inspect the exact prompt (system+user) before it goes out over the network
        JsonObject requestBody = buildOllamaRequestBody(incidentText);

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(OLLAMA_CHAT_COMPLETIONS_URL))
                .header("Authorization", "Bearer " + System.getenv("OLLAMA_API_KEY"))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(requestBody.toString()))
                .build();

        HttpResponse<String> response;
        try {
            response = HTTP_CLIENT.send(request, HttpResponse.BodyHandlers.ofString());
        } catch (IOException | InterruptedException e) {
            throw new RuntimeException("Ollama Cloud call failed", e);
        }

        if (response.statusCode() != 200) {
            throw new RuntimeException("Ollama Cloud returned HTTP " + response.statusCode() + ": " + response.body());
        }

        // BREAKPOINT: inspect raw JSON response and extracted content right after the network call returns
        JsonObject responseJson = JsonParser.parseString(response.body()).getAsJsonObject();
        JsonArray choices = responseJson.getAsJsonArray("choices");
        JsonObject firstChoice = choices.get(0).getAsJsonObject();
        String content = firstChoice.getAsJsonObject("message").get("content").getAsString();
        return content;
    }

    private JsonObject buildOllamaRequestBody(String incidentText) {
        JsonObject systemMessage = new JsonObject();
        systemMessage.addProperty("role", "system");
        systemMessage.addProperty("content", SYSTEM_PROMPT);

        JsonObject userMessage = new JsonObject();
        userMessage.addProperty("role", "user");
        userMessage.addProperty("content", incidentText);

        JsonArray messages = new JsonArray();
        messages.add(systemMessage);
        messages.add(userMessage);

        JsonObject body = new JsonObject();
        body.addProperty("model", OLLAMA_MODEL);
        body.add("messages", messages);
        return body;
    }
}
