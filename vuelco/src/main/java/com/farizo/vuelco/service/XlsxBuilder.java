package com.farizo.vuelco.service;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.List;

import org.apache.poi.ss.usermodel.Cell;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.stereotype.Service;

import com.farizo.vuelco.model.Transaction;
import com.farizo.vuelco.pojo.XlsFile;

@Service
public class XlsxBuilder {
    private static final ZoneId buenosAires = ZoneId.of("America/Argentina/Buenos_Aires");
    private static final DateTimeFormatter formatter = DateTimeFormatter.ofPattern("dd-MM-yy");

    public XlsFile generateXlsx(List<Transaction> transactions, String bank) throws IOException {
        try (Workbook workbook = new XSSFWorkbook();
                ByteArrayOutputStream out = new ByteArrayOutputStream()) {

            Sheet sheet = workbook.createSheet("Transacciones");

            String[] cols = { "Fecha", "Descripción", "Importe", "Saldo", "Movimiento", "Imputacion", "Origen" };
            Row header = sheet.createRow(0);
            for (int i = 0; i < cols.length; i++) {
                Cell cell = header.createCell(i);
                cell.setCellValue(cols[i]);
            }

            int rowNum = 1;
            for (Transaction t : transactions) {
                Row row = sheet.createRow(rowNum++);
                row.createCell(0).setCellValue(t.date());
                row.createCell(1).setCellValue(t.description());
                row.createCell(2).setCellValue(t.amount().doubleValue());
                row.createCell(3).setCellValue(t.balance().doubleValue());
                row.createCell(4).setCellValue(t.type().name());
                row.createCell(5).setCellValue(t.imputation());
                row.createCell(6).setCellValue(t.origin());
            }

            for (int i = 0; i < cols.length; i++) {
                sheet.autoSizeColumn(i);
            }

            workbook.write(out);
            String name = buildFileName(bank);
            return new XlsFile(name, out.toByteArray());
        }
    }

    private String buildFileName(String bank) {
        LocalDate todayBA = LocalDate.now(buenosAires);
        String nowFormatted = todayBA.format(formatter);
        return bank + "_" + nowFormatted;
    }

}
