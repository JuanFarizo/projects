package com.farizo.vuelco.utils;

import org.apache.commons.lang3.EnumUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import com.farizo.vuelco.model.Bank;
import com.farizo.vuelco.model.BusinessException;
import com.farizo.vuelco.service.FrancesPdfExtractor;
import com.farizo.vuelco.service.GaliciaPdfExtractor;
import com.farizo.vuelco.service.PatagoniaPdfExtractor;
import com.farizo.vuelco.service.PdfExtractor;

@Component
public class PdfExtractorResolver {
    @Autowired
    private FrancesPdfExtractor francesPdfExtractor;
    @Autowired
    private GaliciaPdfExtractor galiciaPdfExtractor;
    @Autowired
    private PatagoniaPdfExtractor patagoniaPdfExtractor;

    public PdfExtractor get(String bank) {
        Bank bankEn = EnumUtils.getEnum(Bank.class, bank);
        switch (bankEn) {
            case Bank.galicia: 
                return this.galiciaPdfExtractor;
            case Bank.frances:
                return this.francesPdfExtractor;
            case Bank.patagonia:
                return this.patagoniaPdfExtractor;
            default:
                throw new BusinessException("No se puede procesar el pdf para el banco: " + bank, 1, "home");
        }
    }
}
