package com.farizo.vuelco.pojo;

import java.math.BigDecimal;

public class Transaction {

    private String date;
    private String description;
    private BigDecimal amount;
    private BigDecimal balance;
    private TransactionType type;
    private String imputation;

    public Transaction() {
    }

    public Transaction(
            String date,
            String description,
            BigDecimal amount,
            BigDecimal balance,
            TransactionType type,
            String imputation
    ) {
        this.date = date;
        this.description = description;
        this.amount = amount;
        this.balance = balance;
        this.type = type;
        this.imputation = imputation;
    }

    public String getDate() {
        return date;
    }

    public void setDate(String date) {
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

    public String getImputation() {
        return imputation;
    }

    public void setImputation(String imputation) {
        this.imputation = imputation;
    }
}