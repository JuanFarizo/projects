package com.farizo.vuelco.controller;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

import org.apache.poi.ss.usermodel.Cell;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.multipart.MultipartFile;

import com.farizo.vuelco.pojo.Transaction;
import com.farizo.vuelco.service.PdfStatementExtractor;

import jakarta.servlet.http.HttpSession;

@Controller
public class HomeController {

    @Autowired
    private PdfStatementExtractor pdfStatementExtractor;

    @GetMapping("/")
    public String home(Model model) {
        model.addAttribute("step", 1);
        return "home";
    }

    @PostMapping("/upload")
    public String handleUpload(
            @RequestParam("files") List<MultipartFile> files,
            Model model,
            HttpSession session) throws Exception {

        if (files == null || files.stream().allMatch(MultipartFile::isEmpty)) {
            model.addAttribute("step", 1);
            model.addAttribute("error", "Por favor seleccione al menos un archivo PDF.");
            return "home";
        }

        List<Transaction> allTransactions = new ArrayList<>();
        List<String> processedFiles = new ArrayList<>();

        for (MultipartFile file : files) {
            if (!file.isEmpty()) {
                List<Transaction> transactions = pdfStatementExtractor.extract(file.getInputStream());
                allTransactions.addAll(transactions);
                processedFiles.add(file.getOriginalFilename());
                transactions.forEach(t ->
                    System.out.println(
                        t.getDate() + " | " +
                        t.getType() + " | " +
                        t.getAmount() + " | " +
                        t.getBalance() + " | " +
                        t.getDescription() + " | " +
                        t.getImputation()
                    )
                );
            }
        }

        session.setAttribute("transactions", allTransactions);

        model.addAttribute("step", 2);
        model.addAttribute("transactionCount", allTransactions.size());
        model.addAttribute("fileCount", processedFiles.size());
        model.addAttribute("processedFiles", processedFiles);

        return "home";
    }

    @GetMapping("/download")
    public ResponseEntity<byte[]> download(HttpSession session) throws IOException {
        @SuppressWarnings("unchecked")
        List<Transaction> transactions = (List<Transaction>) session.getAttribute("transactions");

        if (transactions == null || transactions.isEmpty()) {
            return ResponseEntity.badRequest().build();
        }

        byte[] xlsx = generateXlsx(transactions);

        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"extracto_vuelco.xlsx\"")
                .contentType(MediaType.parseMediaType(
                        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"))
                .body(xlsx);
    }

    private byte[] generateXlsx(List<Transaction> transactions) throws IOException {
        try (Workbook workbook = new XSSFWorkbook();
             ByteArrayOutputStream out = new ByteArrayOutputStream()) {

            Sheet sheet = workbook.createSheet("Transacciones");

            String[] cols = {"Fecha", "Descripción", "Tipo", "Monto", "Saldo", "Imputacion"};
            Row header = sheet.createRow(0);
            for (int i = 0; i < cols.length; i++) {
                Cell cell = header.createCell(i);
                cell.setCellValue(cols[i]);
            }

            int rowNum = 1;
            for (Transaction t : transactions) {
                Row row = sheet.createRow(rowNum++);
                row.createCell(0).setCellValue(t.getDate().toString());
                row.createCell(1).setCellValue(t.getDescription());
                row.createCell(2).setCellValue(t.getType().name());
                row.createCell(3).setCellValue(t.getAmount().doubleValue());
                row.createCell(4).setCellValue(t.getBalance().doubleValue());
                row.createCell(5).setCellValue(t.getImputation());
            }

            for (int i = 0; i < cols.length; i++) {
                sheet.autoSizeColumn(i);
            }

            workbook.write(out);
            return out.toByteArray();
        }
    }
}
