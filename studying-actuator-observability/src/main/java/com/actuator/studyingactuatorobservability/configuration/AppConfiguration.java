package com.actuator.studyingactuatorobservability.configuration;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.support.RestClientAdapter;
import org.springframework.web.service.invoker.HttpServiceProxyFactory;

import com.actuator.studyingactuatorobservability.post.JsonPlaceholderService;

@Configuration
public class AppConfiguration {

    @Bean
    JsonPlaceholderService jsonPlaceholderService() {
        RestClient restClient = RestClient.create("https://jsonplaceholder.typicode.com");
        HttpServiceProxyFactory factory = HttpServiceProxyFactory.builderFor(RestClientAdapter.create(restClient)).build();
        return factory.createClient(JsonPlaceholderService.class);
    }

}
