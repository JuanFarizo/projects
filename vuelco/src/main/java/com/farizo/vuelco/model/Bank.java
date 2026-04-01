package com.farizo.vuelco.model;

public enum Bank {
    galicia;

    public static boolean isValidBank(String bank) {
        Bank[] banks = Bank.values();
        for (Bank bankEnum : banks) {
            if(bankEnum.toString().equals(bank)) {
                return true;
            }
        }
        return false;
    }
}
