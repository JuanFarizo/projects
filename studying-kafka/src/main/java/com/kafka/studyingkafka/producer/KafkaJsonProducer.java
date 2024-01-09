package com.kafka.studyingkafka.producer;

import static com.kafka.studyingkafka.config.KafkaTopicConfig.TOPIC_NAME;


import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.KafkaHeaders;
import org.springframework.messaging.Message;
import org.springframework.messaging.support.MessageBuilder;
import org.springframework.stereotype.Component;

import com.kafka.studyingkafka.payload.Student;

import lombok.RequiredArgsConstructor;

@Component
@RequiredArgsConstructor
public class KafkaJsonProducer {
    private final KafkaTemplate<String, Student> template;
    
    public void sendMessage(Student student) {
        Message<Student> message = MessageBuilder
        .withPayload(student)
        .setHeader(KafkaHeaders.TOPIC, TOPIC_NAME)
        .build();
        template.send(message);
    }
}
