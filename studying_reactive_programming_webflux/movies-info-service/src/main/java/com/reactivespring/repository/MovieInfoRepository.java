package com.reactivespring.repository;

import org.springframework.data.mongodb.repository.ReactiveMongoRepository;

import com.reactivespring.domain.MovieInfo;


public interface MovieInfoRepository extends ReactiveMongoRepository<MovieInfo, String> {

}
