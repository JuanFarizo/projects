package com.farizo.vuelco.controller;

import java.io.IOException;
import java.util.List;

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

import com.farizo.vuelco.model.Bank;
import com.farizo.vuelco.model.Transaction;
import com.farizo.vuelco.pojo.ExtractionResult;
import com.farizo.vuelco.pojo.XlsFile;
import com.farizo.vuelco.service.GaliciaPdfExtractor;
import com.farizo.vuelco.service.XlsxBuilder;

import jakarta.servlet.http.HttpSession;

@Controller
public class HomeController {

    @Autowired
    private GaliciaPdfExtractor galiciaPdfExtractor;

    @Autowired
    private XlsxBuilder xlsxBuilder;

    @GetMapping("/")
    public String home(Model model) {
        model.addAttribute("step", 1);
        return "home";
    }

    @PostMapping("/upload")
    public String handleUpload(
            @RequestParam("files") List<MultipartFile> files,
            @RequestParam("banco") String bank,
            Model model,
            HttpSession session) throws Exception {

        if (files == null || files.stream().allMatch(MultipartFile::isEmpty)) {
            model.addAttribute("step", 1);
            model.addAttribute("error", "Por favor seleccione al menos un archivo PDF.");
            return "home";
        }
        Bank.validateBank(bank);

        ExtractionResult result = galiciaPdfExtractor.extract(files);

        session.setAttribute("transactions", result.allTransactions());
        session.setAttribute("bank", bank);

        model.addAttribute("step", 2);
        model.addAttribute("transactionCount", result.allTransactions().size());
        model.addAttribute("fileCount", result.processedFiles().size());
        model.addAttribute("processedFiles", result.processedFiles());

        return "home";
    }

    @GetMapping("/download")
    public ResponseEntity<byte[]> download(HttpSession session) throws IOException {
        @SuppressWarnings("unchecked")
        List<Transaction> transactions = (List<Transaction>) session.getAttribute("transactions");
        String bank = (String) session.getAttribute("bank");

        if (transactions == null || transactions.isEmpty()) {
            return ResponseEntity.badRequest().build();
        }

        XlsFile xlsx = xlsxBuilder.generateXlsx(transactions, bank);

        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + xlsx.name() + ".xlsx\"")
                .contentType(MediaType.parseMediaType(
                        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"))
                .body(xlsx.file());
    }

}
