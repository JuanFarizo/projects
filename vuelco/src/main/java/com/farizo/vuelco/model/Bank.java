package com.farizo.vuelco.model;

public enum Bank {
    galicia;

    public static void validateBank(String bank) {
        Bank[] banks = Bank.values();
        for (Bank bankEnum : banks) {
            if(bankEnum.toString().equals(bank)) {
                return;
            }
        }
        throw new IllegalArgumentException(bank + " no es un banco valido.");
    }
}
