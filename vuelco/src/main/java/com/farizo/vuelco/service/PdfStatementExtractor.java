package com.farizo.vuelco.service;

import java.io.InputStream;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.text.PDFTextStripper;
import org.springframework.stereotype.Service;

import com.farizo.vuelco.pojo.Transaction;
import com.farizo.vuelco.pojo.TransactionType;

@Service
public class PdfStatementExtractor {

    private static final DateTimeFormatter DATE_FORMAT =
            DateTimeFormatter.ofPattern("dd/MM/yy");

    private static final Pattern DATE_LINE =
            Pattern.compile("^(\\d{2}/\\d{2}/\\d{2})\\s+(.*)$");

    private static final Pattern MONEY_LINE =
            Pattern.compile("(-?\\d{1,3}(?:\\.\\d{3})*,\\d{2})\\s+(-?\\d{1,3}(?:\\.\\d{3})*,\\d{2})$");

    public List<Transaction> extract(InputStream inputStream) throws Exception {
        List<Transaction> result = new ArrayList<>();

        try (PDDocument document = PDDocument.load(inputStream)) {
            PDFTextStripper stripper = new PDFTextStripper();

            for (int page = 1; page <= document.getNumberOfPages(); page++) {
                stripper.setStartPage(page);
                stripper.setEndPage(page);

                parsePage(stripper.getText(document), result);
            }
        }
        return result;
    }

    private void parsePage(String text, List<Transaction> out) {
        String[] lines = text.split("\\R");

        LocalDate currentDate = null;
        StringBuilder description = new StringBuilder();

        for (String raw : lines) {
            String line = raw.trim();
            if (line.isEmpty()) continue;

            // skip obvious headers
            if (line.startsWith("Resumen")
                    || line.startsWith("Página")
                    || line.startsWith("CUIT")
                    || line.startsWith("Movimientos")
                    || line.startsWith("Fecha ")) {
                continue;
            }

            // 1️⃣ Date line → start transaction
            Matcher dateMatcher = DATE_LINE.matcher(line);
            if (dateMatcher.matches()) {
                currentDate = LocalDate.parse(dateMatcher.group(1), DATE_FORMAT);
                description.setLength(0);
                description.append(dateMatcher.group(2));
                continue;
            }

            // 2️⃣ Amount + saldo → close transaction
            Matcher moneyMatcher = MONEY_LINE.matcher(line);
            if (moneyMatcher.matches() && currentDate != null) {

                BigDecimal amount = parseMoney(moneyMatcher.group(1));
                BigDecimal balance = parseMoney(moneyMatcher.group(2));

                TransactionType type =
                        amount.signum() >= 0 ? TransactionType.CREDIT : TransactionType.DEBIT;

                out.add(new Transaction(
                        currentDate,
                        description.toString().trim(),
                        amount,
                        balance,
                        type
                ));

                // reset state
                currentDate = null;
                description.setLength(0);
                continue;
            }

            // 3️⃣ Description continuation
            if (currentDate != null) {
                description.append(" ").append(line);
            }
        }
    }

    private BigDecimal parseMoney(String value) {
        return new BigDecimal(
                value.replace(".", "").replace(",", ".")
        );
    }
}
