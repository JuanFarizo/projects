package com.reactivespring.service;

import org.springframework.stereotype.Service;

import com.reactivespring.domain.MovieInfo;
import com.reactivespring.repository.MovieInfoRepository;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

@Service
public class MovieInfoService {

    private MovieInfoRepository movieInfoRepository;

    public MovieInfoService(MovieInfoRepository movieInfoRepository) {
        this.movieInfoRepository = movieInfoRepository;
    }

    public Mono<MovieInfo> addMovieInfo(MovieInfo movieInfo) {
        return movieInfoRepository.save(movieInfo);
    }

    public Flux<MovieInfo> getAllMovieInfos() {
        return movieInfoRepository.findAll().log();
    }

    public Mono<MovieInfo> getAllMovieInfoById(String id) {
        return movieInfoRepository.findById(id);
    }

    public Mono<MovieInfo> updateMovieInfo(MovieInfo updateMovieInfo, String id) {
        return movieInfoRepository.findById(id)
                .flatMap(movieInfo -> { // For doing a transformation that returns another reactive type
                    movieInfo.setCast(updateMovieInfo.getCast());
                    movieInfo.setName(updateMovieInfo.getName());
                    movieInfo.setRelease_date(updateMovieInfo.getRelease_date());
                    movieInfo.setYear(updateMovieInfo.getYear());
                    return movieInfoRepository.save(movieInfo);
                });
    }

    public Mono<Void> deleteMovieInfo(String id) {
        return movieInfoRepository.deleteById(id);
    }

}
