package com.farizo.vuelco.controller;

import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.multipart.MaxUploadSizeExceededException;
import org.springframework.web.multipart.MultipartException;

import com.farizo.vuelco.model.BusinessException;

@ControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(BusinessException.class)
    public String handleBusinessException(BusinessException ex, Model model) {
        model.addAttribute("error", ex.getErrorMessage());
        model.addAttribute("step", ex.getStep());
        return ex.getReturnTemplateView();
    }

    @ExceptionHandler(MaxUploadSizeExceededException.class)
    public String handleMaxUploadSizeExceeded(MaxUploadSizeExceededException ex, Model model) {
        model.addAttribute("error",
                "Se superó el tamaño máximo establecido para la carga de PDF (20 MB por archivo, 50 MB en total).");
        model.addAttribute("step", 1);
        return "home";
    }

    @ExceptionHandler(MultipartException.class)
    public String handleMultipartException(MultipartException ex, Model model) {
        Throwable cause = ex.getRootCause();
        if (cause instanceof MaxUploadSizeExceededException) {
            return handleMaxUploadSizeExceeded((MaxUploadSizeExceededException) cause, model);
        }
        model.addAttribute("error", "No se pudieron procesar los archivos. Verifique el formato y el tamaño.");
        model.addAttribute("step", 1);
        return "home";
    }
}
