package com.reactivespring.router;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.isA;
import static org.mockito.Mockito.when;

import java.net.URI;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.reactive.AutoConfigureWebTestClient;
import org.springframework.boot.test.autoconfigure.web.reactive.WebFluxTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.context.ContextConfiguration;
import org.springframework.test.web.reactive.server.WebTestClient;
import org.springframework.web.util.UriComponentsBuilder;

import com.reactivespring.domain.Review;
import com.reactivespring.exceptionhandler.GlobalExceptionHandler;
import com.reactivespring.handler.ReviewHandler;
import com.reactivespring.repository.ReviewReactiveRepository;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

@WebFluxTest
// Allow inject beans automatically for you
@ContextConfiguration(classes = { ReviewRouter.class, ReviewHandler.class, GlobalExceptionHandler.class })
@AutoConfigureWebTestClient
public class ReviewUnitTest {

    private static final String REVIEWS_URL = "/v1/reviews";

    @MockBean
    private ReviewReactiveRepository reviewReactiveRepository;

    @Autowired
    private WebTestClient webTestClient;

    @Test
    void addReview() {
        Review review = new Review(null, 1L, "Awesome Movie", 9.0);
        when(reviewReactiveRepository.save(isA(Review.class))).thenReturn(Mono.just(review));

        webTestClient.post()
                .uri(REVIEWS_URL)
                .bodyValue(review)
                .exchange()
                .expectStatus()
                .isCreated()
                .expectBody(Review.class)
                .consumeWith(movieInfoResponse -> {
                    Review responseBody = movieInfoResponse.getResponseBody();
                    assertEquals(review.getMovieInfoId(), responseBody.getMovieInfoId());
                    assertEquals(review.getComment(), responseBody.getComment());
                });
    }

    @Test
    void addReview_Validations() {
        Review review = new Review(null, null, "Awesome Movie", -9.0);
        when(reviewReactiveRepository.save(isA(Review.class))).thenReturn(Mono.just(review));

        webTestClient.post()
                .uri(REVIEWS_URL)
                .bodyValue(review)
                .exchange()
                .expectStatus()
                .isBadRequest()
                .expectBody(String.class)
                .isEqualTo("rating.movieInfoId : must not be null,rating.negative : please pass a non-negative value");
    }

    @Test
    void updateReview() {
        String reviewId = "abc";
        Review updateReview = new Review("abc", 2L, "Some comment", 9.0);
        when(reviewReactiveRepository.findById(isA(String.class)))
                .thenReturn(Mono.just(new Review("abc", 2L, "Some comment", 9.0)));
        when(reviewReactiveRepository.save(isA(Review.class))).thenReturn(Mono.just(updateReview));

        webTestClient.put()
                .uri(REVIEWS_URL + "/{id}", reviewId)
                .bodyValue(updateReview)
                .exchange()
                .expectStatus().isOk()
                .expectBody(Review.class);
    }

    @Test
    void deleteReview() {
        String reviewId = "abc";
        when(reviewReactiveRepository.findById(isA(String.class)))
                .thenReturn(Mono.just(new Review("abc", 2L, "Some comment", 9.0)));
        when(reviewReactiveRepository.deleteById(isA(String.class))).thenReturn(Mono.empty());

        webTestClient.delete()
                .uri(REVIEWS_URL + "/{id}", reviewId)
                .exchange()
                .expectStatus().isNoContent()
                .expectBody(Void.class);
    }

    @Test
    void getAllReviews() {
        when(reviewReactiveRepository.findAll()).thenReturn(Flux.just(
                new Review("abc", 2L, "Some comment", 9.0),
                new Review("abc", 2L, "Some comment", 9.0)));

        webTestClient.get()
                .uri(REVIEWS_URL)
                .exchange()
                .expectStatus().isOk()
                .expectBodyList(Review.class)
                .hasSize(2);
    }

    @Test
    void getAllReviewsByMovieInfoId() {
        Long movieInfoId = 2L;
        when(reviewReactiveRepository.findReviewsByMovieInfoId(isA(Long.class))).thenReturn(Flux.just(
                new Review("abc", 2L, "Some comment", 9.0)));

        URI uri = UriComponentsBuilder.fromUriString(REVIEWS_URL).queryParam("movieInfoId", movieInfoId)
                .buildAndExpand().toUri();
        webTestClient.get()
                .uri(uri)
                .exchange()
                .expectStatus().isOk()
                .expectBodyList(Review.class)
                .hasSize(1);
    }
}
