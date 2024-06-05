package org.example.greeting.client;

import java.io.IOException;

import com.proto.greeting.GreetingRequest;
import com.proto.greeting.GreetingResponse;
import com.proto.greeting.GreetingServiceGrpc;

import io.grpc.ChannelCredentials;
import io.grpc.Grpc;
import io.grpc.ManagedChannel;
import io.grpc.TlsChannelCredentials;

public class GreetingClientTls {
    private static void doGreet(ManagedChannel channel) {
        System.out.println("Enter doGreet");
        // Stub
        GreetingServiceGrpc.GreetingServiceBlockingStub stub = GreetingServiceGrpc.newBlockingStub(channel);
        GreetingResponse response = stub.greet(GreetingRequest.newBuilder().setFirstName("Juan").build());
        System.out.println("Greeting response: " + response.getResult());
    }

    public static void main(String[] args) throws IOException {
        if (args.length == 0) {
            System.out.println("Need one argument to work");
            return;
        }
        // Channels are objects that will create the TCP connection between the client
        // and the server
        ChannelCredentials cc = TlsChannelCredentials
                .newBuilder()
                .trustManager(new java.io.File("ssl/ca.crt"))
                .build();
        ManagedChannel channel = Grpc.newChannelBuilderForAddress("localhost", 50051, cc).build();

        switch (args[0]) {
            case "greet":
                doGreet(channel);
                break;
            default:
                System.out.println("Keyword invalid" + args[0]);
                break;
        }

        System.out.println("Shutting down");
        channel.shutdown();
    }

}
