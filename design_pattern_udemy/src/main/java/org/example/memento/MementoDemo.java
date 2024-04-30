package org.example.memento;

// Is the Memento
class BankAccountToken {
    public int balance;

    public BankAccountToken(int balance) {
        this.balance = balance;
    }
}

class BankAccountMemento {
    private int balance;

    public BankAccountMemento(int balance) {
        this.balance = balance;
    }

    public BankAccountToken deposit(int amount) {
        balance += amount;
        return new BankAccountToken(balance);
    }

    public void restore(BankAccountToken memento) {
        balance = memento.balance;
    }

    //Essentially what you can do is you can have each operation, such as the deposit operation,
    // for example, return a snapshot of the internal state of the bank account
    // so that this snapshot can be used to restore the bank account to  a previous   state .

    @Override
    public String toString() {
        return "BankAccountMemento{" +
                "balance=" + balance +
                '}';
    }
}

public class MementoDemo {
    public static void main(String[] args) {
        BankAccountMemento ba = new BankAccountMemento(100);
        BankAccountToken m1 = ba.deposit(50);
        BankAccountToken m2 = ba.deposit(25);
        System.out.println(ba);
        // Restore to m1
        ba.restore(m1);
        System.out.println(ba);
        ba.restore(m2);
        System.out.println(ba);
    }
}
