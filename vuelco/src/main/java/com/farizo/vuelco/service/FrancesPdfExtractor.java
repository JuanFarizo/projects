package com.farizo.vuelco.service;

import java.util.List;

import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import com.farizo.vuelco.pojo.ExtractionResult;

@Service
public class FrancesPdfExtractor implements PdfExtractor{

    @Override
    public ExtractionResult extract(List<MultipartFile> files) throws Exception {
        // TODO Auto-generated method stub
        throw new UnsupportedOperationException("Unimplemented method 'extract'");
    }
    
}
