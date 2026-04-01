package com.farizo.vuelco.service;

import java.util.List;

import org.springframework.web.multipart.MultipartFile;

import com.farizo.vuelco.pojo.ExtractionResult;

public interface PdfExtractor {
    ExtractionResult extract(List<MultipartFile> files) throws Exception;
}
