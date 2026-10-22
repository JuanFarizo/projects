package demo.billing;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;

// P3 test runner fixture (tests/checks/60_tests_runner.lua): one pass, one failure on purpose.
// Tagged so `mvn test` skips it (pom.xml surefire excludedGroups); the editor test runner runs it.
@Tag("nv4j-failing")
class PriceCalculatorFailingTest {
    private final PriceCalculator calculator = new PriceCalculator();

    @Test
    void passes() {
        assertEquals(6, calculator.total(new Invoice(2, 3)));
    }

    @Test
    void failsOnPurpose() {
        int total = calculator.total(new Invoice(2, 3));
        assertEquals(7, total, "P3 fixture: fails on purpose");
    }
}
