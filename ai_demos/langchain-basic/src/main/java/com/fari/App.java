package com.fari;

import java.util.Collections;
import java.util.concurrent.CompletableFuture;

import dev.langchain4j.model.chat.response.ChatResponse;
import dev.langchain4j.model.chat.response.StreamingChatResponseHandler;
import dev.langchain4j.model.ollama.OllamaStreamingChatModel;

public class App {
    static String ollamaKey = System.getenv("OLLAMA_API_KEY");
    static String OLLAMA_MODEL_NAME = "gpt-oss:20b-cloud";
    static String OLLAMA_BASE_URL = "https://ollama.com";
    public static void main(String[] args) {
        OllamaStreamingChatModel ollamaChatModel = OllamaStreamingChatModel.builder()
                .baseUrl(OLLAMA_BASE_URL)
                .modelName(OLLAMA_MODEL_NAME)
                .customHeaders(Collections.singletonMap("Authorization", "Bearer " + ollamaKey))
                .build();
        String userMessage = "List top 10 cities in China";
        CompletableFuture<Object> futureResponse = new CompletableFuture<>();
        ollamaChatModel.chat(userMessage, new StreamingChatResponseHandler() {

            @Override
            public void onCompleteResponse(ChatResponse completeResponse) {
                futureResponse.complete(completeResponse);
            }

            @Override
            public void onError(Throwable error) {
                futureResponse.completeExceptionally(error);
            }

        });
        futureResponse.join();
    }
}
