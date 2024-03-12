package com.actuator.studyingactuatorobservability;

import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;

import com.actuator.studyingactuatorobservability.post.JsonPlaceholderService;
import com.actuator.studyingactuatorobservability.post.Post;

import io.micrometer.observation.annotation.Observed;

@SpringBootApplication
public class StudyingActuatorObservabilityApplication {

	private static final Logger log = LoggerFactory.getLogger(StudyingActuatorObservabilityApplication.class);

	public static void main(String[] args) {
		SpringApplication.run(StudyingActuatorObservabilityApplication.class, args);
	}

	@Bean
	@Observed(name = "posts.load-all-posts", contextualName = "post.find-all")
	CommandLineRunner commandLineRunner(JsonPlaceholderService jsonPlaceholderService) {
		return args -> {
			List<Post> posts = jsonPlaceholderService.findAll();
			log.info("Posts: {}", posts.size());
		};
	}
}
