package com.kafka.studyingkafka.consumer;

import static com.kafka.studyingkafka.config.KafkaTopicConfig.TOPIC_NAME;

import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

import com.kafka.studyingkafka.payload.Student;

import lombok.extern.slf4j.Slf4j;

@Component
@Slf4j
public class KafkaConsumer {
    // @KafkaListener(topics = TOPIC_NAME, groupId = "myGroup")
    public void consumeMsg(String message) {
        log.info(String.format("This is the messege consumed %s", message));
    }

    @KafkaListener(topics = TOPIC_NAME, groupId = "myGroup")
    public void consumeJsonMsg(Student student) {
        log.info(String.format("This is the messege consumed %s", student.toString()));
    }
}
