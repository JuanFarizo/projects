package demo.shop;

import demo.billing.Invoice;
import demo.billing.PriceCalculator;

// P3: call sites in another package (tests/checks/62_refactor.lua): imports to update on rename/move,
// calls to update on change signature. Also the class the scaffold "test" kind targets (61_scaffold).
public class Checkout {
    private final PriceCalculator calculator = new PriceCalculator();

    public int pay(int quantity, int unitPrice) {
        return calculator.total(new Invoice(quantity, unitPrice));
    }

    public int payTwice(Invoice invoice) {
        return calculator.total(invoice) + calculator.total(invoice);
    }
}
