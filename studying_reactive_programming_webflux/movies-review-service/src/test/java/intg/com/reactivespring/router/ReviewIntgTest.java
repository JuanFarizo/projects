package com.reactivespring.router;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.net.URI;
import java.util.List;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.reactive.AutoConfigureWebTestClient;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.reactive.server.WebTestClient;
import org.springframework.web.util.UriComponentsBuilder;

import com.reactivespring.domain.Review;
import com.reactivespring.repository.ReviewReactiveRepository;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("test")
@AutoConfigureWebTestClient
public class ReviewIntgTest {

    private static final String REVIEWS_URL = "/v1/reviews";

    @Autowired
    WebTestClient webTestClient;

    @Autowired
    ReviewReactiveRepository reviewReactiveRepository;

    @BeforeEach
    void setUp() {
        List<Review> reviewList = List.of(
                new Review(null, 1L, "Awesome movie", 9.0),
                new Review(null, 1L, "Awesome movie1", 9.0),
                new Review("abc", 2L, "Excellent movie", 8.0));
        reviewReactiveRepository.saveAll(reviewList).blockLast();
    }

    @AfterEach
    void tearDown() {
        reviewReactiveRepository.deleteAll()
                .block();
    }

    @Test
    void addReview() {
        Review review = new Review(null, 1L, "Awesome Movie", 9.0);

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
    void getAllReviews() {
        webTestClient.get()
                .uri(REVIEWS_URL)
                .exchange()
                .expectStatus()
                .isOk()
                .expectBodyList(Review.class)
                .hasSize(3);
    }

    @Test
    void getAllReviewsMovieInfoId() {
        URI uri = UriComponentsBuilder.fromUriString(REVIEWS_URL).queryParam("movieInfoId", 2L).buildAndExpand()
                .toUri();

        webTestClient.get()
                .uri(uri)
                .exchange()
                .expectStatus()
                .isOk()
                .expectBodyList(Review.class)
                .hasSize(1);
    }

    @Test
    void updateReview() {
        Review updateReview = new Review(null, 3L, "Spetacula a a ar", 10.0);
        String reviewId = "abc";

        webTestClient.put()
                .uri(REVIEWS_URL + "/{id}", reviewId)
                .bodyValue(updateReview)
                .exchange()
                .expectStatus().isOk()
                .expectBody(Review.class)
                .consumeWith(reviewResponse -> {
                    Review reviewUpdated = reviewResponse.getResponseBody();
                    assertEquals(reviewUpdated.getComment(), updateReview.getComment());
                });
    }

    @Test
    void deleteReview() {
        String movieInfoId = "abc";

        webTestClient.delete()
                .uri(REVIEWS_URL + "/{id}", movieInfoId)
                .exchange()
                .expectStatus().isNoContent()
                .expectBody(Void.class);
    }
}
