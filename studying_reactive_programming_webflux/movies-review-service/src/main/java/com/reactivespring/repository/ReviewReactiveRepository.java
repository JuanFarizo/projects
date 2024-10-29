package com.reactivespring.repository;

import org.springframework.data.mongodb.repository.ReactiveMongoRepository;

import com.reactivespring.domain.Review;

public interface ReviewReactiveRepository extends ReactiveMongoRepository<Review, String> {

}
