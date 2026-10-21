package demo;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

// Debug target of tests/checks/40_debug.lua (JUnit case): a plain JUnit 5 test, no Spring context.
class GreetingPropertiesTest {

    @Test
    void keepsText() {
        GreetingProperties props = new GreetingProperties("hi", 2);
        String text = props.text();
        assertEquals("hi", text);
    }
}
