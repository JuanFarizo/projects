package com.farizo.vuelco.model;

public class BusinessException extends RuntimeException {
    private String errorMessage;
    private int step;
    private String returnTemplateView;

    public BusinessException(String errorMessage, int step, String returnTemplateView) {
        super(errorMessage);
        this.errorMessage = errorMessage;
        this.step = step;
        this.returnTemplateView = returnTemplateView;
    }

    public String getErrorMessage() {
        return errorMessage;
    }

    public int getStep() {
        return step;
    }

    public String getReturnTemplateView() {
        return returnTemplateView;
    }
}
