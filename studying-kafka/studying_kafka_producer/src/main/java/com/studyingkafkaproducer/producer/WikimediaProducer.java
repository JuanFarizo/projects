package com.studyingkafkaproducer.producer;

import static com.studyingkafkaproducer.producer.config.TopicConfig.TOPIC_NAME;

import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

@Component
@RequiredArgsConstructor
public class WikimediaProducer {

    private final KafkaTemplate<String, String> kafkaTemplate;

    public void sendMessage(String message) {
        // log.info(String.format("This is the message produced: %s", message));
        kafkaTemplate.send(TOPIC_NAME, message);
    }
}
