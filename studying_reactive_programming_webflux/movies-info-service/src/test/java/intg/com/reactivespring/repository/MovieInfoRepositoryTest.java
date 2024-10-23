package com.reactivespring.repository;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import java.time.LocalDate;
import java.util.List;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.data.mongo.DataMongoTest;
import org.springframework.test.context.ActiveProfiles;

import com.reactivespring.domain.MovieInfo;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

@DataMongoTest // Scan the app and look for the repository classes
@ActiveProfiles("test")
class MovieInfoRepositoryTest {

    @Autowired
    MovieInfoRepository movieInfoRepository;

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
    void findAllTest() {
        Flux<MovieInfo> movieInfoFlux = movieInfoRepository.findAll().log();

        StepVerifier.create(movieInfoFlux)
                .expectNextCount(3l)
                .verifyComplete();

    }

    @Test
    void findByIdTest() {
        Mono<MovieInfo> monoMovieInfo = movieInfoRepository.findById("abc");

        StepVerifier.create(monoMovieInfo)
                .assertNext(movieInfo -> {
                    assertEquals("Batman Ends", movieInfo.getName());
                })
                .verifyComplete();

    }

    @Test
    void saveMovieInfoTest() {
        MovieInfo newMovieInfo = new MovieInfo(null, "Batman el malote", 2005, List.of("Cris", "El pingui"),
                LocalDate.parse("2005-06-15"));
        Mono<MovieInfo> savedMovieInfo = movieInfoRepository.save(newMovieInfo).log();

        StepVerifier.create(savedMovieInfo)
                .assertNext(movieInfo -> {
                    assertNotNull(movieInfo.getMovieInfoId());
                    assertEquals("Batman el malote", movieInfo.getName());
                })
                .verifyComplete();

    }

    @Test
    void updateMovieInfoTest() {
        MovieInfo movieInfo = movieInfoRepository.findById("abc").block();
        movieInfo.setYear(2024);

        Mono<MovieInfo> monoSavedMovieInfo = movieInfoRepository.save(movieInfo);

        StepVerifier.create(monoSavedMovieInfo)
                .assertNext(monoMovieInfo -> {
                    assertEquals(2024, monoMovieInfo.getYear());
                })
                .verifyComplete();
    }

    @Test
    void deleteMovieInfo() {
        movieInfoRepository.deleteById("abc").block(); // When use block, the execution blocks until finish

        Flux<MovieInfo> fluxMovieInfo = movieInfoRepository.findAll().log();
        StepVerifier.create(fluxMovieInfo)
                .expectNextCount(2)
                .verifyComplete();

    }

}