package com.reentrantlock;

import java.util.Random;
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReentrantLock;
import javafx.application.Application;
import javafx.stage.Stage;

public class PricesContainerMain extends Application {
    public static void main(String[] args) {
//        launch(args);
        System.out.println("Testing");
    }

    @Override
    public void start(Stage stage) throws Exception {

    }
}

class PricesContainer {
    private Lock lockobject = new ReentrantLock();
    private double bitcoinPrice;
    private double ehterPrice;
    private double litecoinPrice;
    private double bitcoinCashprice;
    private double ripplePrice;

    public Lock getLockobject() {
        return lockobject;
    }

    public void setLockobject(Lock lockobject) {
        this.lockobject = lockobject;
    }

    public double getBitcoinPrice() {
        return bitcoinPrice;
    }

    public void setBitcoinPrice(double bitcoinPrice) {
        this.bitcoinPrice = bitcoinPrice;
    }

    public double getEhterPrice() {
        return ehterPrice;
    }

    public void setEhterPrice(double ehterPrice) {
        this.ehterPrice = ehterPrice;
    }

    public double getLitecoinPrice() {
        return litecoinPrice;
    }

    public void setLitecoinPrice(double litecoinPrice) {
        this.litecoinPrice = litecoinPrice;
    }

    public double getBitcoinCashprice() {
        return bitcoinCashprice;
    }

    public void setBitcoinCashprice(double bitcoinCashprice) {
        this.bitcoinCashprice = bitcoinCashprice;
    }

    public double getRipplePrice() {
        return ripplePrice;
    }

    public void setRipplePrice(double ripplePrice) {
        this.ripplePrice = ripplePrice;
    }
}

class PriceUpdater extends Thread {
    private PricesContainer pricesContainer;
    private Random random = new Random();

    public PriceUpdater(PricesContainer pricesContainer) {
        this.pricesContainer = pricesContainer;
    }

    @Override
    public void run() {
        while (true) {
            pricesContainer.getLockobject().lock();
            try {
                try {
                    Thread.sleep(1000);
                } catch (InterruptedException ignored) {
                }
                pricesContainer.setBitcoinPrice(random.nextInt(20000));
                pricesContainer.setEhterPrice(random.nextInt(2000));
                pricesContainer.setLitecoinPrice(random.nextInt(500));
                pricesContainer.setBitcoinCashprice(random.nextInt(5000));
                pricesContainer.setRipplePrice(random.nextDouble());
            } finally {
                pricesContainer.getLockobject().unlock();
            }
        }
    }
}
