package com.reactivespring.controller;

import java.time.LocalDate;
import java.util.List;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.reactive.AutoConfigureWebTestClient;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.reactive.server.WebTestClient;

import com.reactivespring.domain.MovieInfo;
import com.reactivespring.repository.MovieInfoRepository;

//This allow us to load the context and use a random port to it
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
// So make sure you provide active profile and make sure this profile is
// different from all the profiles
// that you have provided in the application dot Yaml file.
@ActiveProfiles("Test")
@AutoConfigureWebTestClient
public class MovieInfoControllerTest {

    private static final String MOVIE_INFO_URI = "/v1/movieinfos";

    @Autowired
    MovieInfoRepository movieInfoRepository;

    @Autowired
    WebTestClient webTestClient;

    @BeforeEach
    void setUp() {
        List<MovieInfo> movieInfos = List.of(
                new MovieInfo(null, "Batman Begins", 2005, List.of("Cris", "Miguel"), LocalDate.parse("2005-06-15")),
                new MovieInfo(null, "Dark Knight", 2008, List.of("Cris", "El Risas"), LocalDate.parse("2008-07-18")),
                new MovieInfo("abc", "Batman Ends", 2012, List.of("Cris", "Tomasito"),
                        LocalDate.parse("2012-07-20")));
        movieInfoRepository.saveAll(movieInfos).blockLast();
    }

    @AfterEach
    void tearDown() {
        movieInfoRepository.deleteAll().block();
    }

    @Test
    void addMovieInfo() {
        MovieInfo movieInfo = new MovieInfo(null, "Just Created", 2005, List.of("Cris", "Miguel"),
                LocalDate.parse("2005-06-15"));

        webTestClient.post()
                .uri(MOVIE_INFO_URI)
                .bodyValue(movieInfo)
                .exchange()
                .expectStatus().isCreated()
                .expectBody(MovieInfo.class)
                .consumeWith(exchangeResult -> {
                    MovieInfo movieInfoResponse = exchangeResult.getResponseBody();
                    Assertions.assertNotNull(movieInfoResponse.getMovieInfoId());
                });
    }

    @Test
    void addMovieInfoValidation() {
        MovieInfo movieInfo = new MovieInfo(null, "", 2005, List.of(""),
                LocalDate.parse("2005-06-15"));

        webTestClient.post()
                .uri(MOVIE_INFO_URI)
                .bodyValue(movieInfo)
                .exchange()
                .expectStatus().isBadRequest()
                .expectBody(String.class)
                .consumeWith(exchangeResult -> {
                    String responseBody = exchangeResult.getResponseBody();
                    Assertions.assertEquals("Movie cast must not be empty, The name must be present", responseBody);
                });
    }

    @Test
    void getAllMovieInfos() {
        webTestClient.get()
                .uri(MOVIE_INFO_URI)
                .exchange()
                .expectStatus()
                .is2xxSuccessful()
                .expectBodyList(MovieInfo.class)
                .hasSize(3);
    }

    @Test
    void getMovieInfoById() {
        String movieInfoId = "abc";
        webTestClient.get()
                .uri(MOVIE_INFO_URI + "/{id}", movieInfoId)
                .exchange()
                .expectStatus()
                .is2xxSuccessful()
                .expectBody(MovieInfo.class)
                .consumeWith(exchangeResult -> {
                    MovieInfo responseBody = exchangeResult.getResponseBody();
                    Assertions.assertEquals(movieInfoId, responseBody.getMovieInfoId());
                });

        // Alternatively
        webTestClient.get()
                .uri(MOVIE_INFO_URI + "/{id}", movieInfoId)
                .exchange()
                .expectStatus()
                .is2xxSuccessful()
                .expectBody()
                .jsonPath("$.name").isEqualTo("Batman Ends");
    }

    @Test
    void updateMovieInfoById() {
        String newMovieName = "Just Updated";
        String movieInfoId = "abc";
        MovieInfo movieInfo = new MovieInfo(null, newMovieName, 2222, List.of("Cris", "Miguel"),
                LocalDate.parse("2020-06-15"));

        webTestClient.put()
                .uri(MOVIE_INFO_URI + "/{id}", movieInfoId)
                .bodyValue(movieInfo)
                .exchange()
                .expectStatus().is2xxSuccessful()
                .expectBody(MovieInfo.class)
                .consumeWith(exchangeResult -> {
                    MovieInfo movieInfoResponse = exchangeResult.getResponseBody();
                    Assertions.assertEquals(newMovieName, movieInfoResponse.getName());
                    Assertions.assertEquals(movieInfoId, movieInfoResponse.getMovieInfoId());
                });
    }

    @Test
    void deleteMovieInfoById() {
        String movieInfoId = "abc";

        webTestClient.delete()
                .uri(MOVIE_INFO_URI + "/{id}", movieInfoId)
                .exchange()
                .expectStatus().isNoContent()
                .expectBody(Void.class);
    }
}
