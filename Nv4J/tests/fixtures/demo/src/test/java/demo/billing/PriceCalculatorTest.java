package demo.billing;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

// P3 test runner fixture (tests/checks/60_tests_runner.lua): all green. 5 passing runs (1 plain,
// 3 parameterized invocations, 1 nested) and 1 disabled.
class PriceCalculatorTest {
    private final PriceCalculator calculator = new PriceCalculator();

    @Test
    void totalMultiplies() {
        assertEquals(6, calculator.total(new Invoice(2, 3)));
    }

    @ParameterizedTest
    @ValueSource(ints = { 1, 2, 3 })
    void totalOfOneUnit(int quantity) {
        assertEquals(quantity, calculator.total(new Invoice(quantity, 1)));
    }

    @Nested
    class WhenEmpty {
        @Test
        void totalIsZero() {
            assertEquals(0, calculator.total(new Invoice(0, 5)));
        }
    }

    @Disabled("P3 fixture: a skipped test")
    @Test
    void notYet() {
        assertEquals(1, 2);
    }
}
