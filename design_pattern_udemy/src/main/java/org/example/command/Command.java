package org.example.command;

import com.google.common.collect.Lists;
import java.util.List;

class BankAccountC {
    private int balance;
    private final int overdraftLimit = -500;

    public void deposit(int amount) {
        balance += amount;
        System.out.println("Deposited " + amount + " balance is now " + balance);
    }

    public boolean withdraw(int amount) {
        if (balance - amount >= overdraftLimit) {
            balance -= amount;
            System.out.println("Withdrew " + amount + " balance is now " + balance);
            return true;
        }
        return false;
    }

    @Override
    public String toString() {
        return "BankAccountC{" + "balance=" + balance + "}";
    }
}

interface CommandC {
    void call();

    void undo();
}

class BankAccountCommandC implements CommandC {
    private final BankAccountC account;
    private boolean succeeded;

    @Override
    public void call() {
        switch (action) {
            case DEPOSIT -> {
                succeeded = true;
                account.deposit(amount);
            }
            case WITHDRAW -> succeeded = account.withdraw(amount);
        }
    }

    @Override
    public void undo() {
        if (!succeeded)
            return;
        switch (action) {
            case DEPOSIT -> account.withdraw(amount);
            case WITHDRAW -> account.deposit(amount);
        }
    }

    public enum Action {
        DEPOSIT, WITHDRAW
    }

    private final Action action;
    private final int amount;

    public BankAccountCommandC(BankAccountC account, Action action, int amount) {
        this.account = account;
        this.action = action;
        this.amount = amount;
    }
}

public class Command {
    public static void main(String[] args) {
        BankAccountC ba = new BankAccountC();
        System.out.println(ba);
        List<BankAccountCommandC> commands = List.of(new BankAccountCommandC(ba, BankAccountCommandC.Action.DEPOSIT, 100),
                new BankAccountCommandC(ba, BankAccountCommandC.Action.WITHDRAW, 1000));
        for (BankAccountCommandC command : commands) {
            command.call();
            System.out.println(ba);
        }

        for (BankAccountCommandC command : Lists.reverse(commands)) {
            command.undo();
            System.out.println(ba);
        }
    }
}
