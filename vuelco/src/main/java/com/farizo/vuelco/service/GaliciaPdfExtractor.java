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
import org.springframework.web.multipart.MultipartFile;

import com.farizo.vuelco.model.Transaction;
import com.farizo.vuelco.model.TransactionType;
import com.farizo.vuelco.pojo.ExtractionResult;
import com.farizo.vuelco.utils.ImputationResolver;

@Service
public class GaliciaPdfExtractor implements PdfExtractor {

    private static final DateTimeFormatter DATE_FORMAT = DateTimeFormatter.ofPattern("dd/MM/yy");

    private static final Pattern DATE_LINE = Pattern.compile("^(\\d{2}/\\d{2}/\\d{2})\\s+(.*)$");

    private static final Pattern MONEY_LINE = Pattern
            .compile("(-?\\d{1,3}(?:\\.\\d{3})*,\\d{2})\\s+(-?\\d{1,3}(?:\\.\\d{3})*,\\d{2})$");

    @Override
    public ExtractionResult extract(List<MultipartFile> files) throws Exception {
        List<Transaction> allTransactions = new ArrayList<>();
        List<String> processedFiles = new ArrayList<>();

        for (MultipartFile file : files) {
            if (!file.isEmpty()) {
                List<Transaction> transactions = this.extractFile(file.getInputStream(),
                        file.getOriginalFilename());
                allTransactions.addAll(transactions);
                processedFiles.add(file.getOriginalFilename());
            }
        }
        return new ExtractionResult(allTransactions, processedFiles);
    }

    private List<Transaction> extractFile(InputStream inputStream, String origin) throws Exception {
        List<Transaction> result = new ArrayList<>();

        try (PDDocument document = PDDocument.load(inputStream)) {
            PDFTextStripper stripper = new PDFTextStripper();

            for (int page = 1; page <= document.getNumberOfPages(); page++) {
                stripper.setStartPage(page);
                stripper.setEndPage(page);

                parsePage(stripper.getText(document), result, origin);
            }
        }
        return result;
    }

    private void parsePage(String text, List<Transaction> out, String origin) {
        String[] lines = text.split("\\R");

        LocalDate currentDate = null;
        String testData = "";
        StringBuilder description = new StringBuilder();

        for (String raw : lines) {
            String line = raw.trim();
            if (line.isEmpty())
                continue;
            // skip obvious headers
            if (line.startsWith("Resumen")
                    || line.startsWith("Página")
                    || line.startsWith("CUIT")
                    || line.startsWith("Movimientos")
                    || line.startsWith("Fecha ")) {
                continue;
            }

            // 1 Date line → start transaction
            Matcher dateMatcher = DATE_LINE.matcher(line);
            if (dateMatcher.matches()) {
                testData = dateMatcher.group(1);
                currentDate = LocalDate.parse(testData, DATE_FORMAT);
                description.setLength(0);

                String rest = dateMatcher.group(2);
                Matcher inlineMoneyMatcher = MONEY_LINE.matcher(rest);
                if (inlineMoneyMatcher.find()) {
                    // All info is on this single line — close transaction immediately
                    String descPart = rest.substring(0, inlineMoneyMatcher.start()).trim();
                    {
                        BigDecimal amount = parseMoney(inlineMoneyMatcher.group(1));
                        BigDecimal balance = parseMoney(inlineMoneyMatcher.group(2));
                        TransactionType type = amount.signum() >= 0 ? TransactionType.credito : TransactionType.debito;
                        out.add(new Transaction(
                                testData,
                                descPart,
                                amount,
                                balance,
                                type,
                                ImputationResolver.resolver(descPart),
                                origin));
                    }
                    currentDate = null;
                } else {
                    description.append(rest);
                }
                continue;
            }

            // 2 Amount + saldo → close transaction
            Matcher moneyMatcher = MONEY_LINE.matcher(line);
            if (moneyMatcher.find() && currentDate != null) {

                BigDecimal amount = parseMoney(moneyMatcher.group(1));
                BigDecimal balance = parseMoney(moneyMatcher.group(2));

                TransactionType type = amount.signum() >= 0 ? TransactionType.credito : TransactionType.debito;

                out.add(new Transaction(
                        testData,
                        description.toString().trim(),
                        amount,
                        balance,
                        type,
                        ImputationResolver.resolver(description.toString().trim()),
                        origin));

                // reset state
                currentDate = null;
                description.setLength(0);
                continue;
            }

            // 3 Description continuation
            if (currentDate != null) {
                description.append(" ").append(line);
            }
        }
    }

    private BigDecimal parseMoney(String value) {
        return new BigDecimal(
                value.replace(".", "").replace(",", "."));
    }
}
