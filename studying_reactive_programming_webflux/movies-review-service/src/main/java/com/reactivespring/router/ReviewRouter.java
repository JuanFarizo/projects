package com.reactivespring.router;

import static org.springframework.web.reactive.function.server.RouterFunctions.route;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.reactive.function.server.RequestPredicates;
import org.springframework.web.reactive.function.server.RouterFunction;
import org.springframework.web.reactive.function.server.ServerResponse;

import com.reactivespring.handler.ReviewHandler;

@Configuration
public class ReviewRouter {
    @Bean
    public RouterFunction<ServerResponse> reviewRoute(ReviewHandler reviewHandler) {
        return route()
                .nest(RequestPredicates.path("/v1/reviews"), builder -> {
                    builder.POST("", req -> reviewHandler.addReview(req))
                            .GET("", req -> reviewHandler.getReviews(req))
                            .PUT("/{id}", req -> reviewHandler.updateReview(req))
                            .DELETE("/{id}", req -> reviewHandler.deleteReview(req));
                })
                .GET("/v1/helloworld", (req -> ServerResponse.ok().bodyValue("Hello World")))
                .build();
    }
}
