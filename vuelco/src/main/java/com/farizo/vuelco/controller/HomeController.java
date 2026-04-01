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

import com.farizo.vuelco.config.UploadPayloadLimitFilter;
import com.farizo.vuelco.model.Bank;
import com.farizo.vuelco.model.BusinessException;
import com.farizo.vuelco.model.Transaction;
import com.farizo.vuelco.pojo.ExtractionResult;
import com.farizo.vuelco.pojo.XlsFile;
import com.farizo.vuelco.service.XlsxBuilder;
import com.farizo.vuelco.utils.PdfExtractorResolver;

import jakarta.servlet.http.HttpSession;

@Controller
public class HomeController {

    @Autowired
    private PdfExtractorResolver pdfExtractorResolver;

    @Autowired
    private XlsxBuilder xlsxBuilder;

    @GetMapping("/")
    public String home(Model model, HttpSession session) {
        Object flashError = session.getAttribute(UploadPayloadLimitFilter.SESSION_FLASH_ERROR);
        if (flashError != null) {
            model.addAttribute("error", flashError);
            Object step = session.getAttribute(UploadPayloadLimitFilter.SESSION_FLASH_STEP);
            model.addAttribute("step", step != null ? step : 1);
            session.removeAttribute(UploadPayloadLimitFilter.SESSION_FLASH_ERROR);
            session.removeAttribute(UploadPayloadLimitFilter.SESSION_FLASH_STEP);
            return "home";
        }
        model.addAttribute("step", 1);
        return "home";
    }

    @PostMapping("/upload")
    public String handleUpload(
            @RequestParam("files") List<MultipartFile> files,
            @RequestParam("banco") String bank,
            Model model,
            HttpSession session) {

        if (bank.equals("patagonia")) throw new BusinessException("Aun estamos trabajando en el procesamiento del extracto del banco patagonia", 1, "home");
        if (files == null || files.stream().allMatch(MultipartFile::isEmpty)) {
            throw new BusinessException(
                    "Por favor seleccione al menos un archivo PDF.", 1, "home");
        }
        if (!Bank.isValidBank(bank)) {
            throw new BusinessException("Por favor seleccione un banco.", 1, "home");
        }

        ExtractionResult result;
        try {
            result = pdfExtractorResolver.get(bank).extract(files);
        } catch (Exception e) {
            throw new BusinessException("Hubo un error al procesar el PDF.", 1, "home");
        }

        session.setAttribute("transactions", result.allTransactions());
        session.setAttribute("bank", bank);

        model.addAttribute("step", 2);
        model.addAttribute("transactionCount", result.allTransactions().size());
        model.addAttribute("fileCount", result.processedFiles().size());
        model.addAttribute("processedFiles", result.processedFiles());

        return "home";
    }

    @GetMapping("/download")
    public ResponseEntity<byte[]> download(HttpSession session) {
        @SuppressWarnings("unchecked")
        List<Transaction> transactions = (List<Transaction>) session.getAttribute("transactions");
        String bank = (String) session.getAttribute("bank");

        if (transactions == null || transactions.isEmpty()) {
            return ResponseEntity.badRequest().build();
        }

        XlsFile xlsx;
        try {
            xlsx = xlsxBuilder.generateXlsx(transactions, bank);
        } catch (IOException e) {
            throw new BusinessException("Hubo un error al generar el archivo Excel.", 1, "home");
        }

        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + xlsx.name() + ".xlsx\"")
                .contentType(MediaType.parseMediaType(
                        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"))
                .body(xlsx.file());
    }

}
