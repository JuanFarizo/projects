package com.resilience.studying;

import java.util.concurrent.TimeoutException;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;

import io.github.resilience4j.bulkhead.BulkheadFullException;
import io.github.resilience4j.circuitbreaker.CallNotPermittedException;
import io.github.resilience4j.ratelimiter.RequestNotPermitted;

@ControllerAdvice
public class ApiExceptionHandler {

    @ExceptionHandler({ CallNotPermittedException.class })
    @ResponseStatus(HttpStatus.SERVICE_UNAVAILABLE)
    public void handleCallNotPermittedException() {
        System.out.println("The services is Unavailable");
    }

    @ExceptionHandler({ TimeoutException.class })
    @ResponseStatus(HttpStatus.REQUEST_TIMEOUT)
    public void handleTimeoutException() {
        System.out.println("Service time out");
    }

    @ExceptionHandler({ BulkheadFullException.class })
    @ResponseStatus(HttpStatus.BANDWIDTH_LIMIT_EXCEEDED)
    public void handleBulkheadFullException() {
        System.out.println("Bandwith limit exceeded");
    }

    @ExceptionHandler({ RequestNotPermitted.class })
    @ResponseStatus(HttpStatus.TOO_MANY_REQUESTS)
    public void handleRequestNotPermitted() {
        System.out.println("Request not permitted");
    }

}
