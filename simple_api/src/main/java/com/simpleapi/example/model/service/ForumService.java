package com.simpleapi.example.model.service;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.simpleapi.example.model.PostRecord;
import com.simpleapi.example.model.entity.Post;
import com.simpleapi.example.repository.PostRepository;

import jakarta.persistence.EntityNotFoundException;

@Service
@Transactional(readOnly = true)
public class ForumService {
    @Autowired
    private PostRepository postRepository;

    public PostRecord findPostRecordById(Long postId) {
        return postRepository.findWithCommentsById(postId).map(Post::toRecord)
                .orElseThrow(() -> new EntityNotFoundException(
                        String.format("Post with id %s not found", postId)));
    }

    @Transactional
    public PostRecord insertPostRecord(PostRecord postRecord) {
        return postRepository.save(postRecord.toPost()).toRecord();
    }

    @Transactional
    public PostRecord mergePostRecord(PostRecord postRecord) {
        return postRepository.findById(postRecord.id())
                .orElseThrow(
                        () -> new EntityNotFoundException(String.format("Post not found with id %s", postRecord.id())))
                .setTitle(postRecord.title())
                .toRecord();
    }
}
