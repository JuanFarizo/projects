package com.resilience.studying;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.stream.IntStream;

import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.RegisterExtension;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import com.github.tomakehurst.wiremock.client.WireMock;
import com.github.tomakehurst.wiremock.core.WireMockConfiguration;
import com.github.tomakehurst.wiremock.junit5.WireMockExtension;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
public class ResilientAppControllerUnitTest {

    @Autowired
    private TestRestTemplate template;

    @RegisterExtension
    static WireMockExtension EXTERNAL_SERVICE = WireMockExtension.newInstance()
            .options(WireMockConfiguration.wireMockConfig().port(8000))
            .build();

    private Logger LOGGER = LoggerFactory.getLogger(this.getClass());

    @Test
    void circuitBreakerOther() {
        EXTERNAL_SERVICE.stubFor(WireMock.get("/api/external").willReturn(WireMock.serverError()));
        IntStream.range(1, 5)
                .forEach(i -> {
                    ResponseEntity<String> response = template.getForEntity("/api/circuit-breaker-second",
                            String.class);
                    Assertions.assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
                });

        IntStream.range(1, 5)
                .forEach(i -> {
                    ResponseEntity<String> response = template.getForEntity("/api/circuit-breaker-second",
                            String.class);
                    Assertions.assertThat(response.getStatusCode()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
                });

        EXTERNAL_SERVICE.verify(5, WireMock.getRequestedFor(WireMock.urlEqualTo("/api/external")));
    }

    @Test
    void testCircuitBreaker() {
        EXTERNAL_SERVICE.stubFor(WireMock.get("/api/external").willReturn(WireMock.serverError()));

        IntStream.range(1, 5)
                .forEach(i -> {
                    ResponseEntity<String> response = template.getForEntity("/api/circuit-breaker", String.class);
                    Assertions.assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
                });

        IntStream.range(1, 5)
                .forEach(i -> {
                    ResponseEntity<String> response = template.getForEntity("/api/circuit-breaker", String.class);
                    Assertions.assertThat(response.getStatusCode()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
                });

        EXTERNAL_SERVICE.verify(5, WireMock.getRequestedFor(WireMock.urlEqualTo("/api/external")));
    }

    @Test
    void testRetry() {
        EXTERNAL_SERVICE.stubFor(WireMock.get("/api/external").willReturn(WireMock.ok()));
        template.getForEntity("/api/retry", String.class);
        EXTERNAL_SERVICE.verify(1, WireMock.getRequestedFor(WireMock.urlEqualTo("/api/external")));

        EXTERNAL_SERVICE.resetRequests();

        EXTERNAL_SERVICE.stubFor(WireMock.get("/api/external").willReturn(WireMock.serverError()));
        ResponseEntity<String> response2 = template.getForEntity("/api/retry", String.class);

        org.junit.jupiter.api.Assertions.assertEquals(response2.getBody(), "all retries have exhausted");
        EXTERNAL_SERVICE.verify(3, WireMock.getRequestedFor(WireMock.urlEqualTo("/api/external")));
    }

    @Test
    void testTimeLimiter() {
        EXTERNAL_SERVICE.stubFor(WireMock.get("/api/external").willReturn(WireMock.ok()));
        ResponseEntity<String> response = template.getForEntity("/api/time-limiter", String.class);

        Assertions.assertThat(response.getStatusCode()).isEqualTo(HttpStatus.REQUEST_TIMEOUT);
        EXTERNAL_SERVICE.verify(1, WireMock.getRequestedFor(WireMock.urlEqualTo("/api/external")));
    }

    @Test
    void testBulkhead() throws InterruptedException {
        EXTERNAL_SERVICE.stubFor(WireMock.get("/api/external").willReturn(WireMock.ok()));
        Map<Integer, Integer> responseStatusCount = new ConcurrentHashMap<>();
        ExecutorService service = Executors.newFixedThreadPool(5);
        CountDownLatch latch = new CountDownLatch(5);

        IntStream.range(1, 5)
                .forEach(i -> service.execute(() -> {
                    ResponseEntity<String> response = template.getForEntity("/api/bulkhead", String.class);
                    int statusCode = response.getStatusCode().value();
                    responseStatusCount.merge(statusCode, 1, Integer::sum);
                    latch.countDown();
                }));

        latch.await();
        service.shutdown();
        assertEquals(2, responseStatusCount.keySet().size());
        LOGGER.info("Response statuses: " + responseStatusCount.keySet());
        assertTrue(responseStatusCount.containsKey(HttpStatus.BANDWIDTH_LIMIT_EXCEEDED.value()));
        assertTrue(responseStatusCount.containsKey(HttpStatus.OK.value()));
        EXTERNAL_SERVICE.verify(3, WireMock.getRequestedFor(WireMock.urlEqualTo("/api/external")));
    }

    @Test
    void testRateLimiter() {
        EXTERNAL_SERVICE.stubFor(WireMock.get("/api/external").willReturn(WireMock.ok()));
        Map<Integer, Integer> responseStatusCount = new ConcurrentHashMap<>();
        IntStream.rangeClosed(1, 50)
                .parallel()
                .forEach(i -> {
                    ResponseEntity<String> response = template.getForEntity("/api/rate-limiter", String.class);
                    int statusCode = response.getStatusCode().value();
                    responseStatusCount.put(statusCode, responseStatusCount.getOrDefault(statusCode, 0) + 1);
                });

        assertEquals(2, responseStatusCount.keySet().size());
        assertTrue(responseStatusCount.containsKey(HttpStatus.TOO_MANY_REQUESTS.value()));
        assertTrue(responseStatusCount.containsKey(HttpStatus.OK.value()));
        EXTERNAL_SERVICE.verify(5, WireMock.getRequestedFor(WireMock.urlEqualTo("/api/external")));
    }
}
