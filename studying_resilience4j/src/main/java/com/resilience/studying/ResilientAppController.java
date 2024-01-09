package com.resilience.studying;

import java.util.concurrent.CompletableFuture;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import io.github.resilience4j.bulkhead.annotation.Bulkhead;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.ratelimiter.annotation.RateLimiter;
import io.github.resilience4j.retry.annotation.Retry;
import io.github.resilience4j.timelimiter.annotation.TimeLimiter;

@RestController
@RequestMapping("/api")
public class ResilientAppController {

    private final ExternalAPICaller apiCaller;

    public ResilientAppController(ExternalAPICaller apiCaller) {
        this.apiCaller = apiCaller;
    }

    /*
     * The circuit breaker pattern protects a downstream service by restricting the
     * upstream service from calling the downstream service during a partial or
     * complete downtime.
     */
    @GetMapping("/circuit-breaker")
    @CircuitBreaker(name = "CircuitBreakerService")
    public String circuitBreakerAPI() {
        return apiCaller.callApi();
    }

    @GetMapping("/circuit-breaker-second")
    @CircuitBreaker(name = "myCircuitBreaker")
    public String circuitBreakerAPISecond() {
        return apiCaller.callApi();
    }

    /**
     * Use the time limiter pattern to set a threshold timeout value for async calls
     * made to external systems.
     */
    @GetMapping("/time-limiter")
    @TimeLimiter(name = "timeLimiterApi")
    public CompletableFuture<String> timeLimiterApi() {
        return CompletableFuture.supplyAsync(apiCaller::callApiWithDelay);
    }

    /*
     * The retry pattern provides resiliency to a system by recovering from
     * transient issues
     */
    @GetMapping("/retry")
    @Retry(name = "retryApi", fallbackMethod = "fallbackAfterRetry") // Optional can provide the fallback mechanism
    public String retryApi() {
        return apiCaller.callApi();
    }

    public String fallbackAfterRetry(Exception ex) {
        return "all retries have exhausted";
    }

    /*
     * The bulkhead pattern limits the maximum number of concurrent calls to an
     * external service.
     */
    @GetMapping("/bulkhead")
    @Bulkhead(name = "bulkheadapi")
    public String bulkheadApi() {
        return apiCaller.callApi();
    }

    /*
     * The rate limiter pattern limits the rate of requests to a resource.
     */
    @GetMapping("/rate-limiter")
    @RateLimiter(name = "rateLimiterApi")
    public String rateLimiterApi() {
        return apiCaller.callApi();
    }

}
