package com.simpleapi.example.model.entity;

import java.util.ArrayList;
import java.util.List;

import com.simpleapi.example.model.PostCommentRecord;
import com.simpleapi.example.model.PostRecord;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;

// To Use records with Spring data-JPA
@Entity(name = "Post")
@Table(name = "post")
public class Post {

    @Id
    private Long id;

    private String title;

    @OneToMany(mappedBy = "post", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<PostComment> comments = new ArrayList<>();

    public Long getId() {
        return id;
    }

    public Post setId(Long id) {
        this.id = id;
        return this;
    }

    public String getTitle() {
        return title;
    }

    public Post setTitle(String title) {
        this.title = title;
        return this;
    }

    public List<PostComment> getComments() {
        return comments;
    }

    public Post addComment(PostComment comment) {
        comments.add(comment);
        comment.setPost(this);
        return this;
    }

    public PostRecord toRecord() {
        return new PostRecord(
                id,
                title,
                comments.stream().map(comment -> new PostCommentRecord(
                        comment.getId(),
                        comment.getReview())).toList());
    }
}