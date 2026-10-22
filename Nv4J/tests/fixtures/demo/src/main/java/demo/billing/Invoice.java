package demo.billing;

// P3 refactor target (tests/checks/62_refactor.lua): renamed and moved to another package by the
// check, which restores the fixture afterwards. Used from demo.shop.Checkout (an import to update).
public class Invoice {
    private final int quantity;
    private final int unitPrice;

    public Invoice(int quantity, int unitPrice) {
        this.quantity = quantity;
        this.unitPrice = unitPrice;
    }

    public int quantity() {
        return quantity;
    }

    public int unitPrice() {
        return unitPrice;
    }
}
