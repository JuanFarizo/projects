package com.kafka.studyingkafka.config;

import org.apache.kafka.clients.admin.NewTopic;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.config.TopicBuilder;

@Configuration
public class KafkaTopicConfig {
    public final static String TOPIC_NAME = "alibou";
    
    @Bean
    public NewTopic alibouTopic() {
        return TopicBuilder
        .name(TOPIC_NAME)
        .build();
    }
}
