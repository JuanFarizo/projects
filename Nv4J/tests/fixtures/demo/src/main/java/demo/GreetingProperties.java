package demo;

import org.springframework.boot.context.properties.ConfigurationProperties;

// Bound from application.properties / application-dev.yml (demo.greeting.*).
@ConfigurationProperties(prefix = "demo.greeting")
public record GreetingProperties(String text, int times) {
}
