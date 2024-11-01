package com.reactivespring;

import org.junit.jupiter.api.Test;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Sinks;

public class SinkTest {
    @Test
    void test_sink() {
        Sinks.Many<Integer> replaySink = Sinks.many().replay().all(); // Create a sink

        replaySink.emitNext(1, Sinks.EmitFailureHandler.FAIL_FAST); // Like a producer send next event
        replaySink.emitNext(2, Sinks.EmitFailureHandler.FAIL_FAST); // Like a producer send next event

        Flux<Integer> integerFlux = replaySink.asFlux(); // Consume the events emitted 
        Flux<Integer> integerFlux2 = replaySink.asFlux();

        integerFlux.subscribe(i -> System.out.println("Testing sink: " + i));
        integerFlux2.subscribe(i -> System.out.println("Testing sink: " + i));
    }
}
