package com.simpleapi.example.repository;

import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import com.simpleapi.example.model.entity.Post;

// To Use records with Spring data-JPA
@Repository
public interface PostRepository extends JpaRepository<Post, Long> {
    @Query("""
            select p
            from Post p
            join fetch p.comments
            where p.id = :postId
            """)
    Optional<Post> findWithCommentsById(
            @Param("postId") Long postId);
}
