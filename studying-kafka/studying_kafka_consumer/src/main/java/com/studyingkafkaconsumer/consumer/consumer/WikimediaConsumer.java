package com.studyingkafkaconsumer.consumer.consumer;

import static com.studyingkafkaconsumer.consumer.config.TopicConfig.TOPIC_NAME;

import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

import lombok.extern.slf4j.Slf4j;

@Component
@Slf4j
public class WikimediaConsumer {

    @KafkaListener(topics = TOPIC_NAME, groupId = "myGroup")
    public void consumeMsg(String msg) {
        log.info(String.format("Consuming from wikimedia stream topic:: %s", msg));
    }
}
