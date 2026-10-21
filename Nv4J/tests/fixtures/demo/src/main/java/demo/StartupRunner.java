package demo;

import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

// Runs once the context is up. tests/checks/40_debug.lua sets its breakpoint on the `started` line.
@Component
public class StartupRunner implements ApplicationRunner {
    private final GreetingProperties properties;

    public StartupRunner(GreetingProperties properties) {
        this.properties = properties;
    }

    @Override
    public void run(ApplicationArguments args) {
        String started = "nv4j-started " + properties.text();
        System.out.println(started);
    }
}
