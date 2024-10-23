package com.reactivespring.controller;

import java.util.List;

import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.reactive.AutoConfigureWebTestClient;
import org.springframework.boot.test.autoconfigure.web.reactive.WebFluxTest;
import org.springframework.test.web.reactive.server.WebTestClient;

import reactor.core.publisher.Flux;
import reactor.test.StepVerifier;

@WebFluxTest(controllers = FluxMonoController.class) // It's going to give you access to all the endpoints
@AutoConfigureWebTestClient
class FluxMonoControllerTest {

    @Autowired
    WebTestClient webTestClient;

    @Test
    void flux() {
        webTestClient.get()
                .uri("/flux")
                .exchange()
                .expectStatus().is2xxSuccessful()
                .expectBodyList(Integer.class)
                .hasSize(3);
    }

    @Test
    void flux_test_response_body() {
        Flux<Integer> flux = webTestClient.get()
                .uri("/flux")
                .exchange()
                .expectStatus().is2xxSuccessful()
                .returnResult(Integer.class)
                .getResponseBody();

        StepVerifier.create(flux)
                .expectNext(1, 2, 3)
                .verifyComplete();
    }

    @Test
    void flux_test_response_body2() {
        webTestClient.get()
                .uri("/flux")
                .exchange()
                .expectStatus().is2xxSuccessful()
                .expectBodyList(Integer.class)
                .consumeWith(exchangeResult -> {
                    List<Integer> responseBody = exchangeResult.getResponseBody();
                    Assertions.assertEquals(3, responseBody.size());
                });
    }

    @Test
    void mono() {
        webTestClient.get()
                .uri("/mono")
                .exchange()
                .expectStatus().is2xxSuccessful()
                .expectBody(String.class)
                .consumeWith(exchangeResult -> {
                    String responseBody = exchangeResult.getResponseBody();
                    Assertions.assertEquals("Hello World!", responseBody);
                });
    }

    @Test
    void stream_test_response() {
        Flux<Long> fluxStream = webTestClient.get()
                .uri("/stream")
                .exchange()
                .expectStatus().is2xxSuccessful()
                .returnResult(Long.class)
                .getResponseBody();

        StepVerifier.create(fluxStream)
                .expectNext(0L, 1L, 2L, 3L)
                .thenCancel()
                .verify();
    }

}
