package org.example.greeting.client;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

import com.proto.calculator.AverageRequest;
import com.proto.calculator.AverageResponse;
import com.proto.calculator.CalculatorRequest;
import com.proto.calculator.CalculatorResponse;
import com.proto.calculator.CalculatorServiceGrpc;
import com.proto.calculator.CalculatorServiceGrpc.CalculatorServiceBlockingStub;
import com.proto.calculator.CalculatorServiceGrpc.CalculatorServiceStub;
import com.proto.calculator.MaxRequest;
import com.proto.calculator.MaxResponse;
import com.proto.calculator.PrimeRequest;
import com.proto.calculator.SqrtRequest;
import com.proto.calculator.SqrtResponse;
import com.proto.greeting.GreetingRequest;
import com.proto.greeting.GreetingResponse;
import com.proto.greeting.GreetingServiceGrpc;
import com.proto.greeting.GreetingServiceGrpc.GreetingServiceBlockingStub;
import com.proto.greeting.GreetingServiceGrpc.GreetingServiceStub;

import io.grpc.Deadline;
import io.grpc.ManagedChannel;
import io.grpc.ManagedChannelBuilder;
import io.grpc.Status;
import io.grpc.StatusRuntimeException;
import io.grpc.stub.StreamObserver;

public class GreetingClient {
    private static void doGreet(ManagedChannel channel) {
        System.out.println("Enter doGreet");
        // Stub
        GreetingServiceGrpc.GreetingServiceBlockingStub stub = GreetingServiceGrpc.newBlockingStub(channel);
        GreetingResponse response = stub.greet(GreetingRequest.newBuilder().setFirstName("Juan").build());
        System.out.println("Greeting response: " + response.getResult());
    }

    private static void doCalculate(ManagedChannel channel) {
        System.out.println("Enter doCalculate");
        CalculatorServiceBlockingStub stub = CalculatorServiceGrpc.newBlockingStub(channel);
        CalculatorResponse response = stub.calculate(CalculatorRequest.newBuilder().setA(10).setB(15).build());
        System.out.println("Calculator response " + response.getResult());
    }

    private static void doGreetManyTimes(ManagedChannel channel) {
        System.out.println("Enter doGreetManyTimes");
        GreetingServiceGrpc.GreetingServiceBlockingStub stub = GreetingServiceGrpc.newBlockingStub(channel);
        stub.greetManyTimes(GreetingRequest.newBuilder().setFirstName("PepeTrueno").build())
                .forEachRemaining(response -> {
                    System.out.println("doGreetManyTimes response " + response.getResult());
                });
    }

    private static void doPrime(ManagedChannel channel) {
        System.out.println("Enter doPrime");
        CalculatorServiceBlockingStub stub = CalculatorServiceGrpc.newBlockingStub(channel);
        stub.prime(PrimeRequest.newBuilder().setNum(120).build()).forEachRemaining(response -> {
            System.out.println("doPrime response " + response.getResult());
        });
    }

    private static void doLongGreet(ManagedChannel channel) throws InterruptedException {
        System.out.println("Enter doLongGreet");
        GreetingServiceStub stub = GreetingServiceGrpc.newStub(channel);
        ArrayList<String> nameList = new ArrayList<>();
        Collections.addAll(nameList, "Pepe", "Juan", "Rayo", "Manteca");
        CountDownLatch latch = new CountDownLatch(1);
        StreamObserver<GreetingRequest> stream = stub.longGreet(new StreamObserver<GreetingResponse>() {
            @Override
            public void onNext(GreetingResponse response) {
                System.out.println(response.getResult());
            }

            @Override
            public void onError(Throwable t) {
            }

            @Override
            public void onCompleted() {
                latch.countDown();
            }
        });

        for (String name : nameList) {
            stream.onNext(GreetingRequest.newBuilder().setFirstName(name).build());
        }
        stream.onCompleted();
        latch.await(3, TimeUnit.SECONDS);
    }

    private static void doAverage(ManagedChannel channel) throws InterruptedException {
        System.out.println("Enter doAverage");
        CalculatorServiceStub stub = CalculatorServiceGrpc.newStub(channel);
        ArrayList<Integer> integerList = new ArrayList<>(Arrays.asList(7, 9, 11, 3, 8));
        CountDownLatch latch = new CountDownLatch(1);
        StreamObserver<AverageRequest> stream = stub.average(new StreamObserver<AverageResponse>() {
            @Override
            public void onNext(AverageResponse response) {
                System.out.println(response.getResult());
            }

            @Override
            public void onError(Throwable t) {
            }

            @Override
            public void onCompleted() {
                latch.countDown();
            }
        });
        for (Integer integer : integerList) {
            stream.onNext(AverageRequest.newBuilder().setNum(integer).build());
        }
        stream.onCompleted();
        latch.await(3, TimeUnit.SECONDS);
    }

    private static void doGreetEveryone(ManagedChannel channel) throws InterruptedException {
        System.out.println("Enter doGreetEveryone");
        GreetingServiceStub stub = GreetingServiceGrpc.newStub(channel);
        CountDownLatch latch = new CountDownLatch(1);
        StreamObserver<GreetingRequest> stream = stub.greetEveryone(new StreamObserver<GreetingResponse>() {
            @Override
            public void onNext(GreetingResponse response) {
                System.out.println("Response: " + response.getResult());
            }

            @Override
            public void onError(Throwable t) {

            }

            @Override
            public void onCompleted() {
                latch.countDown();
            }
        });
        Arrays.asList("Pepe", "Juan", "Mayonesa").forEach(
                name -> stream.onNext(GreetingRequest.newBuilder().setFirstName(name).build()));
        stream.onCompleted();
        latch.await(3, TimeUnit.SECONDS);
    }

    private static void doMax(ManagedChannel channel) throws InterruptedException {
        System.out.println("Enter doMax");
        CalculatorServiceStub stub = CalculatorServiceGrpc.newStub(channel);
        CountDownLatch latch = new CountDownLatch(1);
        StreamObserver<MaxRequest> stream = stub.max(new StreamObserver<MaxResponse>() {
            @Override
            public void onNext(MaxResponse response) {
                System.out.println("Max num: " + response.getResult());
            }

            @Override
            public void onError(Throwable t) {
            }

            @Override
            public void onCompleted() {
                latch.countDown();
            }

        });
        Arrays.asList(1, 5, 3, 6, 2, 20).forEach(
                num -> stream.onNext(MaxRequest.newBuilder().setNum(num).build()));
        stream.onCompleted();
        latch.await(3, TimeUnit.SECONDS);
    }

    private static void doSqrt(ManagedChannel channel) {
        System.out.println("Enter doMax");
        CalculatorServiceBlockingStub stub = CalculatorServiceGrpc.newBlockingStub(channel);
        SqrtResponse response = stub.sqrt(SqrtRequest.newBuilder().setNumber(25).build());

        System.out.println("Sqrt of 25 is: " + response.getResult());

        try {
            response = stub.sqrt(SqrtRequest.newBuilder().setNumber(-1).build());
        } catch (RuntimeException e) {
            System.out.println("Get exception for sqrt");
            e.printStackTrace();
        }
    }

    private static void doGreetWithDeadLine(ManagedChannel channel) {
        System.out.println("Enter doGreetWithDeadLine");
        GreetingServiceBlockingStub stub = GreetingServiceGrpc.newBlockingStub(channel);
        GreetingResponse response = stub.withDeadline(Deadline.after(3, TimeUnit.SECONDS))
                .greetWithDeadLine(GreetingRequest.newBuilder().setFirstName("Pepe trueno").build());
        System.out.println("Greeting with deadline: " + response.getResult());

        try {
            response = stub.withDeadline(Deadline.after(100, TimeUnit.MILLISECONDS))
                    .greetWithDeadLine(GreetingRequest.newBuilder().setFirstName("Its going to fail").build());
            System.out.println("Greeting deadline exceeded" + response.getResult());
        } catch (StatusRuntimeException e) {
            if (e.getStatus().getCode() == Status.Code.DEADLINE_EXCEEDED) {
                System.out.println("Deadline has been exceeded");
            } else {
                System.out.println("Got an exception in greeting deadline");
                e.printStackTrace();
            }
        }
    }

    public static void main(String[] args) throws InterruptedException {
        if (args.length == 0) {
            System.out.println("Need one argument to work");
            return;
        }
        // Channels are objects that will create the TCP connection between the client
        // and the server
        ManagedChannel channel = ManagedChannelBuilder.forAddress("localhost", 50051).usePlaintext().build();

        switch (args[0]) {
            case "greet":
                doGreet(channel);
                break;
            case "greetManyTimes":
                doGreetManyTimes(channel);
                break;
            case "calculate":
                doCalculate(channel);
                break;
            case "prime":
                doPrime(channel);
                break;
            case "longGreet":
                doLongGreet(channel);
                break;
            case "average":
                doAverage(channel);
                break;
            case "greetEveryone":
                doGreetEveryone(channel);
                break;
            case "max":
                doMax(channel);
                break;
            case "sqrt":
                doSqrt(channel);
                break;
            case "greetWithDeadLine":
                doGreetWithDeadLine(channel);
                break;
            default:
                System.out.println("Keyword invalid" + args[0]);
                break;
        }

        System.out.println("Shutting down");
        channel.shutdown();
    }

}
