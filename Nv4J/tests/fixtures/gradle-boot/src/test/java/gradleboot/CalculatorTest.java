package gradleboot;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class CalculatorTest {
    private final Calculator calculator = new Calculator();

    @Test
    void adds() {
        assertEquals(5, calculator.add(2, 3));
    }

    @Test
    void multiplies() {
        assertEquals(6, calculator.multiply(2, 3));
    }
}
