package demo.billing;

// P3 refactor targets (tests/checks/62_refactor.lua) and code under test (PriceCalculatorTest):
//  total       : change signature (a parameter added with a default at the call sites in Checkout)
//  gross       : inline method; the local `gross` in total: inline variable
//  legacyTotal : safe delete allowed (no usages); total: safe delete blocked (used in Checkout)
public class PriceCalculator {

    public int total(Invoice invoice) {
        int gross = gross(invoice);
        return gross;
    }

    private int gross(Invoice invoice) {
        return invoice.quantity() * invoice.unitPrice();
    }

    public int legacyTotal(Invoice invoice) {
        return invoice.quantity();
    }
}
