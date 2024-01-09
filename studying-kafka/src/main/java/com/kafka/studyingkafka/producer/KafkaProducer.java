package com.kafka.studyingkafka.producer;

import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import static com.kafka.studyingkafka.config.KafkaTopicConfig.TOPIC_NAME;

@Component
@RequiredArgsConstructor
@Slf4j
public class KafkaProducer {

    private final KafkaTemplate<String, String> template;

    public void sendMessage(String message) {
        log.info(String.format("Sending message to topic: %s, msg: %s", TOPIC_NAME, message));
        template.send(TOPIC_NAME, message);
    }
}
