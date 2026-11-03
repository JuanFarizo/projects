package gradleboot;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;

// 67_gradle fixture: one pass, one failure on purpose. Tagged so `./gradlew test` skips it (build.gradle
// excludeTags); the editor test runner runs it.
@Tag("nv4j-failing")
class CalculatorFailingTest {
    private final Calculator calculator = new Calculator();

    @Test
    void passes() {
        assertEquals(5, calculator.add(2, 3));
    }

    @Test
    void failsOnPurpose() {
        int total = calculator.add(2, 3);
        assertEquals(7, total, "67 fixture: fails on purpose");
    }
}
