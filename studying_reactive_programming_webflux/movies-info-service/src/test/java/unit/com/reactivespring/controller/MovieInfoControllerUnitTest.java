package com.reactivespring.controller;

import static org.mockito.ArgumentMatchers.isA;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.util.List;

import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.reactive.AutoConfigureWebTestClient;
import org.springframework.boot.test.autoconfigure.web.reactive.WebFluxTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.reactive.server.WebTestClient;

import com.reactivespring.domain.MovieInfo;
import com.reactivespring.service.MovieInfoService;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

@WebFluxTest(controllers = MovieInfoController.class)
@AutoConfigureWebTestClient
public class MovieInfoControllerUnitTest {
    private static final String MOVIE_INFO_URI = "/v1/movieinfos";

    @Autowired
    private WebTestClient webTestClient;

    @MockBean
    private MovieInfoService movieInfoService;

    @Test
    void getAllMoviesInfo() {
        List<MovieInfo> movieInfos = List.of(
                new MovieInfo(null, "Batman Begins", 2005, List.of("Cris", "Miguel"), LocalDate.parse("2005-06-15")),
                new MovieInfo(null, "Dark Knight", 2008, List.of("Cris", "El Risas"), LocalDate.parse("2008-07-18")),
                new MovieInfo("abc", "Batman Ends", 2012, List.of("Cris", "Tomasito"),
                        LocalDate.parse("2012-07-20")));

        when(movieInfoService.getAllMovieInfos()).thenReturn(Flux.fromIterable(movieInfos));
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
        when(movieInfoService.getAllMovieInfoById(movieInfoId))
                .thenReturn(Mono.just(new MovieInfo("abc", "Batman Ends", 2012, List.of("Cris", "Tomasito"),
                        LocalDate.parse("2012-07-20"))));

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
    }

    @Test
    void addMovieInfo() {
        MovieInfo movieInfo = new MovieInfo("MockId", "Just Created", 2005, List.of("Cris", "Miguel"),
                LocalDate.parse("2005-06-15"));
        when(movieInfoService.addMovieInfo(isA(MovieInfo.class))).thenReturn(Mono.just(movieInfo));

        webTestClient.post()
                .uri(MOVIE_INFO_URI)
                .bodyValue(movieInfo)
                .exchange()
                .expectStatus().isCreated()
                .expectBody(MovieInfo.class)
                .consumeWith(exchangeResult -> {
                    MovieInfo movieInfoResponse = exchangeResult.getResponseBody();
                    Assertions.assertNotNull(movieInfoResponse.getMovieInfoId());
                    Assertions.assertEquals("MockId", movieInfoResponse.getMovieInfoId());
                    Assertions.assertEquals("Just Created", movieInfoResponse.getName());
                });
    }

    @Test
    void updateMovieInfoById() {
        String newMovieName = "Just Updated";
        String movieInfoId = "abc";
        MovieInfo movieInfo = new MovieInfo("abc", newMovieName, 2222, List.of("Cris", "Miguel"),
                LocalDate.parse("2020-06-15"));

        when(movieInfoService.updateMovieInfo(isA(MovieInfo.class), isA(String.class)))
                .thenReturn(Mono.just(movieInfo));

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

        when(movieInfoService.deleteMovieInfo(movieInfoId)).thenReturn(Mono.empty());

        webTestClient.delete()
                .uri(MOVIE_INFO_URI + "/{id}", movieInfoId)
                .exchange()
                .expectStatus().isNoContent()
                .expectBody(Void.class);
    }
}
