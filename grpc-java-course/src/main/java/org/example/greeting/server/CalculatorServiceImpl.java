package org.example.greeting.server;

import com.proto.calculator.AverageRequest;
import com.proto.calculator.AverageResponse;
import com.proto.calculator.CalculatorRequest;
import com.proto.calculator.CalculatorResponse;
import com.proto.calculator.CalculatorServiceGrpc.CalculatorServiceImplBase;
import com.proto.calculator.MaxRequest;
import com.proto.calculator.MaxResponse;
import com.proto.calculator.PrimeRequest;
import com.proto.calculator.PrimeResponse;
import com.proto.calculator.SqrtRequest;
import com.proto.calculator.SqrtResponse;

import io.grpc.Status;
import io.grpc.stub.StreamObserver;

public class CalculatorServiceImpl extends CalculatorServiceImplBase {

    @Override
    public void calculate(CalculatorRequest request, StreamObserver<CalculatorResponse> responseObserver) {
        responseObserver.onNext(CalculatorResponse.newBuilder().setResult(request.getA() + request.getB()).build());
        responseObserver.onCompleted();
    }

    @Override
    public void prime(PrimeRequest request, StreamObserver<PrimeResponse> responseObserver) {
        int k = 2;
        int N = request.getNum();
        while (N > 1) {
            if (N % k == 0) {
                responseObserver.onNext(PrimeResponse.newBuilder().setResult(k).build());
                N = N / k;
            } else {
                k = k + 1;
            }
        }
        responseObserver.onCompleted();
    }

    @Override
    public StreamObserver<AverageRequest> average(StreamObserver<AverageResponse> responseObserver) {
        return new StreamObserver<AverageRequest>() {
            Integer sum = 0;
            int counter = 0;

            @Override
            public void onNext(AverageRequest request) {
                counter++;
                sum = Integer.sum(sum, request.getNum());
            }

            @Override
            public void onError(Throwable t) {
                responseObserver.onError(t);
            }

            @Override
            public void onCompleted() {
                responseObserver.onNext(AverageResponse.newBuilder().setResult((double) sum / counter).build());
                responseObserver.onCompleted();
            }
        };
    }

    @Override
    public StreamObserver<MaxRequest> max(StreamObserver<MaxResponse> responseObserver) {
        return new StreamObserver<MaxRequest>() {
            int max = Integer.MIN_VALUE;

            @Override
            public void onNext(MaxRequest request) {
                if (max < request.getNum()) {
                    max = request.getNum();
                    responseObserver.onNext(MaxResponse.newBuilder().setResult(max).build());
                }
            }

            @Override
            public void onError(Throwable t) {
                responseObserver.onError(t);
            }

            @Override
            public void onCompleted() {
                responseObserver.onCompleted();
            }

        };
    }

    @Override
    public void sqrt(SqrtRequest request, StreamObserver<SqrtResponse> responseObserver) {
        int number = request.getNumber();
        if (number < 0) {
            responseObserver.onError(
                    Status.INVALID_ARGUMENT
                            .withDescription("The number been send can not be negative")
                            .augmentDescription("Number: " + number)
                            .asRuntimeException());
        }
        responseObserver.onNext(
                SqrtResponse.newBuilder().setResult(Math.sqrt(number)).build());
        responseObserver.onCompleted();
    }

}
