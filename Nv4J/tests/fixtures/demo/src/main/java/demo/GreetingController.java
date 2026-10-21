package demo;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class GreetingController {
    @Value("${demo.greeting.text:Hello}")
    private String text;

    @GetMapping("/hello")
    public String hello() {
        return text;
    }
}
