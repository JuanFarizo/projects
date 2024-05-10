package org.example.recursion;

public sealed interface ShoppingCart {
    record Initial() implements ShoppingCart{}
    record Pending(String productItem) implements ShoppingCart{};
    record Closed() implements ShoppingCart{};
}
