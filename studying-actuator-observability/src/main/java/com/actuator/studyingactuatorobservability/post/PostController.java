package com.actuator.studyingactuatorobservability.post;

import java.util.List;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/posts")
public class PostController {

    private final JsonPlaceholderService jsonPlaceholderService;

    public PostController(JsonPlaceholderService jsonPlaceholderService) {
        this.jsonPlaceholderService = jsonPlaceholderService;
    }

    @GetMapping("")
    public List<Post> findAll() {
        return jsonPlaceholderService.findAll();
    }

    @GetMapping("/{id}")
    public Post findById(@PathVariable Integer id) {
        return jsonPlaceholderService.findById(id);
    }

}
