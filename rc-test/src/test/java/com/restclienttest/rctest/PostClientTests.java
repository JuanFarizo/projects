package com.restclienttest.rctest;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.util.List;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.client.RestClientTest;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.test.web.client.match.MockRestRequestMatchers;
import org.springframework.test.web.client.response.MockRestResponseCreators;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;

@RestClientTest(PostClient.class)
public class PostClientTests {

    @Autowired
    MockRestServiceServer server;

    @Autowired
    PostClient postClient;

    @Autowired
    ObjectMapper objectMapper;

    @Test
    void testFindAll() throws JsonProcessingException {
        // give
        List<Post> posts = List.of(
                new Post(1, 1, "Title post 1", "Body post 1"),
                new Post(1, 2, "Title post 2", "Body post 2"));

        // when
        server.expect(MockRestRequestMatchers.requestTo("https://jsonplaceholder.typicode.com/posts"))
                .andRespond(MockRestResponseCreators.withSuccess(objectMapper.writeValueAsString(posts),
                        org.springframework.http.MediaType.APPLICATION_JSON));
        // then
        List<Post> response = postClient.findAll();
        assertEquals(2, response.size());
    }
}
