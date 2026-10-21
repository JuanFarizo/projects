package demo;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

@Configuration
@EnableConfigurationProperties(GreetingProperties.class)
public class GreetingConfig {
    // Only with the dev profile (application-dev.yml).
    @Bean
    @Profile("dev")
    public String devBanner(GreetingProperties properties) {
        return "dev: " + properties.text();
    }
}
