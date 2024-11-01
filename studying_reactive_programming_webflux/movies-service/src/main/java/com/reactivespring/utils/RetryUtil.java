package com.reactivespring.utils;

import com.reactivespring.exception.MoviesInfoServerException;
import com.reactivespring.exception.ReviewsServerException;

import reactor.core.Exceptions;
import reactor.util.retry.Retry;

public class RetryUtil {
    public static Retry retrySpec() {
        return Retry.fixedDelay(3, java.time.Duration.ofSeconds(1))
                .filter(ex -> ex instanceof MoviesInfoServerException || ex instanceof ReviewsServerException)
                .onRetryExhaustedThrow((retryBackOffSpec, retrySignal) -> Exceptions.propagate(retrySignal.failure()));
    }
}
