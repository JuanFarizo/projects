package com.farizo.vuelco.controller;

import java.io.IOException;
import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.multipart.MultipartFile;

import com.farizo.vuelco.pojo.Transaction;
import com.farizo.vuelco.service.PdfStatementExtractor;

@Controller
public class HomeController {

    @Autowired
    private PdfStatementExtractor pdfStatementExtractor;

    @GetMapping("/")
    public String home() {
        return "home";
    }

    @PostMapping("/upload")
    public String handleUpload(
        @RequestParam("file") MultipartFile file,
        Model model) throws IOException, Exception {
        if (file.isEmpty()) {
            model.addAttribute("message", "Please select a PDF file");
            return "home";
        }

        List<Transaction> transactions = pdfStatementExtractor.extract(file.getInputStream());

        transactions.forEach(t ->
            IO.println(
                t.getDate() + " | " +
                t.getType() + " | " +
                t.getAmount() + " | " +
                t.getBalance() + " | " +
                t.getDescription()
            )
        );

        // later: pass file.getInputStream() to your PDF service

        return "home";

    }
}
