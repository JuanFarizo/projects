package com.farizo.vuelco.pojo;

import java.util.List;

import com.farizo.vuelco.model.Transaction;

public record ExtractionResult(
        List<Transaction> allTransactions,
        List<String> processedFiles) {

}
