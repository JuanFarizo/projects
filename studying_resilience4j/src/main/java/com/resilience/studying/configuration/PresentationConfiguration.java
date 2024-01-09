package com.resilience.studying.configuration;

import java.util.function.Function;

import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;

import com.resilience.studying.ExternalAPICaller;

import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerConfig;
import io.github.resilience4j.circuitbreaker.CircuitBreakerConfig.SlidingWindowType;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;

@Configuration
public class PresentationConfiguration {

    @Bean
    public RestTemplate restTemplate() {
        return new RestTemplateBuilder().rootUri("http://localhost:8000")
                .build();
    }

    CircuitBreakerConfig circuitBreakerConfig = CircuitBreakerConfig.custom()
            .failureRateThreshold(50)
            .minimumNumberOfCalls(5)
            .permittedNumberOfCallsInHalfOpenState(3)
            .slidingWindowSize(10)
            .slidingWindowType(SlidingWindowType.COUNT_BASED)
            .build();

    CircuitBreakerRegistry circuitBreakerRegistry = CircuitBreakerRegistry.of(circuitBreakerConfig);

    CircuitBreaker circuitBreaker = circuitBreakerRegistry.circuitBreaker("myCircuitBreaker");
    Function<ExternalAPICaller, String> decorated = CircuitBreaker
            .decorateFunction(circuitBreaker, ExternalAPICaller::callApi);

}
