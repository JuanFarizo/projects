package com.simpleapi.example.model;

import com.simpleapi.example.model.entity.PostComment;

// To Use records with Spring data-JPA
public record PostCommentRecord(
        Long id,
        String review) {

    PostComment toPostComment() {
        return new PostComment()
                .setId(id)
                .setReview(review);
    }
}
