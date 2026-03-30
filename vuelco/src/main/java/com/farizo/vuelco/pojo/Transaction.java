package com.farizo.vuelco.pojo;

import java.math.BigDecimal;
import java.time.LocalDate;

public class Transaction {

    private LocalDate date;
    private String description;
    private BigDecimal amount;
    private BigDecimal balance;
    private TransactionType type;

    public Transaction() {
    }

    public Transaction(
            LocalDate date,
            String description,
            BigDecimal amount,
            BigDecimal balance,
            TransactionType type
    ) {
        this.date = date;
        this.description = description;
        this.amount = amount;
        this.balance = balance;
        this.type = type;
    }

    public LocalDate getDate() {
        return date;
    }

    public void setDate(LocalDate date) {
        this.date = date;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public void setAmount(BigDecimal amount) {
        this.amount = amount;
    }

    public BigDecimal getBalance() {
        return balance;
    }

    public void setBalance(BigDecimal balance) {
        this.balance = balance;
    }

    public TransactionType getType() {
        return type;
    }

    public void setType(TransactionType type) {
        this.type = type;
    }
}