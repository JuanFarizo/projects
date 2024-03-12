package com.actuator.studyingactuatorobservability.post;

import java.util.List;

import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.service.annotation.GetExchange;


public interface JsonPlaceholderService {

    @GetExchange("/posts")
    List<Post> findAll();

    @GetExchange("posts/{id}")
    Post findById(@PathVariable Integer id);

}
