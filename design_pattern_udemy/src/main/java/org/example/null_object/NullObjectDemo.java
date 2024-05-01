package org.example.null_object;

import java.lang.reflect.Proxy;

interface LogNullObject {
    void info(String msg);

    void warn(String msg);
}

class ConsoleLog implements LogNullObject
{

    @Override
    public void info(String msg)
    {
        System.out.println(msg);
    }

    @Override
    public void warn(String msg)
    {
        System.out.println("WARNING: " + msg);
    }
}

class BankAccountNO {
    private LogNullObject log;
    private int balance;

    public BankAccountNO(LogNullObject log) {
        this.log = log;
    }

    public void deposit(int amount) {
        balance += amount;
        log.info("Deposited amount: $" + amount);
    }

    public void withdraw(int amount) {
        balance -= amount;
        log.info("Withdraw amount: $" + amount);
    }
}

// Dynamic Null Object
@SuppressWarnings("unchecked")
public class NullObjectDemo {
    static <T> T noOp(Class<T> itf) {
        return (T) Proxy.newProxyInstance(
                itf.getClassLoader(),
                new Class<?>[] { itf },
                ((proxy, method, args) -> {
                    if (method.getReturnType().equals(Void.TYPE))
                        return null;
                    else {
                        return method.getReturnType().getConstructor().newInstance();
                    }
                }));
    }

    public static void main(String[] args) {
        LogNullObject log = noOp(LogNullObject.class);
        BankAccountNO bankAccount = new BankAccountNO(log);
        bankAccount.deposit(100);
        bankAccount.withdraw(200);
    }
}
