package com.simpleapi.example.model;

import java.util.List;

import com.simpleapi.example.model.entity.Post;

// To Use records with Spring data-JPA
public record PostRecord(
        Long id,
        String title,
        List<PostCommentRecord> comments) {

    public Post toPost() {
        Post post = new Post()
                .setId(id)
                .setTitle(title);

        comments.forEach(
                comment -> post.addComment(comment.toPostComment()));

        return post;
    }
}
