package com.farizo.vuelco.model;

import java.math.BigDecimal;

public record Transaction(
    String date,
    String description,
    BigDecimal amount,
    BigDecimal balance,
    TransactionType type,
    String imputation,
    String origin
) {}