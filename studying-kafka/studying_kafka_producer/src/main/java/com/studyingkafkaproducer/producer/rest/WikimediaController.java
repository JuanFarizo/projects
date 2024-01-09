package com.studyingkafkaproducer.producer.rest;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.studyingkafkaproducer.producer.stream.WikimediaStreamConsumer;

import lombok.RequiredArgsConstructor;

@RestController
@RequestMapping("/api/v1/wikimedia")
@RequiredArgsConstructor
public class WikimediaController {

    private final WikimediaStreamConsumer streamServiceConsumer;

    @GetMapping("/")
    public ResponseEntity<Void> startPublish() {
        streamServiceConsumer.consumeStreamAndPublish();
        return ResponseEntity.noContent().build();
    }

}
