package org.example.greeting.server;

import java.io.IOException;

import io.grpc.Server;
import io.grpc.ServerBuilder;

public class GreetingServer {
    public static void main(String[] args) throws IOException, InterruptedException {
        int port = 50051;
        Server server = ServerBuilder
                .forPort(port)
                .addService(new GreetingServerImpl())
                .addService(new CalculatorServiceImpl())
                .build();
        server.start();

        System.out.println("Server started");
        System.out.println("Listening on port: " + port);

        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            System.out.println("Received shutdown request");
            server.shutdown();
            System.out.println("Server stoped");
        }));

        server.awaitTermination();
    }
}
