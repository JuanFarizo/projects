package com.reactivespring.handler;

import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.server.ServerRequest;
import org.springframework.web.reactive.function.server.ServerResponse;

import com.reactivespring.domain.Review;
import com.reactivespring.exception.ReviewDataException;
import com.reactivespring.exception.ReviewNotFoundException;
import com.reactivespring.repository.ReviewReactiveRepository;

import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validator;
import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

@Component
@Slf4j
public class ReviewHandler {

    @Autowired
    private Validator validator;

    private ReviewReactiveRepository reactiveReviewRepository;

    public ReviewHandler(ReviewReactiveRepository reactiveRepository) {
        this.reactiveReviewRepository = reactiveRepository;
    }

    public Mono<ServerResponse> addReview(ServerRequest req) {
        return req.bodyToMono(Review.class)
                .doOnNext(this::validate) // Allow us to perform validations
                .flatMap(reactiveReviewRepository::save)
                .flatMap(ServerResponse.status(HttpStatus.CREATED)::bodyValue);
    }

    private void validate(Review review) {
        Set<ConstraintViolation<Review>> constraintViolation = validator.validate(review);
        log.info("Constraint Violation: {}", constraintViolation);
        if (constraintViolation.size() > 0) {
            String errorMessage = constraintViolation.stream()
                    .map(ConstraintViolation::getMessage)
                    .sorted()
                    .collect(Collectors.joining(","));
            throw new ReviewDataException(errorMessage);
        }
    }

    public Mono<ServerResponse> getReviews(ServerRequest req) {
        Optional<String> movieInfoId = req.queryParam("movieInfoId");
        Flux<Review> reviewFlux;
        if (movieInfoId.isPresent()) {
            reviewFlux = reactiveReviewRepository.findReviewsByMovieInfoId(Long.valueOf(movieInfoId.get()));
        } else {
            reviewFlux = reactiveReviewRepository.findAll();
        }
        return ServerResponse.ok().body(reviewFlux, Review.class);
    }

    public Mono<ServerResponse> updateReview(ServerRequest req) {
        String reviewId = req.pathVariable("id");
        Mono<Review> existingReview = reactiveReviewRepository.findById(reviewId)
                .switchIfEmpty(Mono
                        .error(new ReviewNotFoundException("Review not found for the given Review id " + reviewId)));

        return existingReview
                .flatMap(review -> req.bodyToMono(Review.class)
                        .map(reqReview -> {
                            review.setComment(reqReview.getComment());
                            review.setRating(reqReview.getRating());
                            return review;
                        })
                        .flatMap(reactiveReviewRepository::save)
                        .flatMap(ServerResponse.ok()::bodyValue));
    }

    public Mono<ServerResponse> deleteReview(ServerRequest req) {
        String reviewId = req.pathVariable("id");
        Mono<Review> existingReview = reactiveReviewRepository.findById(reviewId);

        return existingReview.flatMap(review -> reactiveReviewRepository.deleteById(reviewId))
                .then(ServerResponse.noContent().build());
    }

}
