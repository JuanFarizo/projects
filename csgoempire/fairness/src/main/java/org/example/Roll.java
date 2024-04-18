package org.example;

import java.time.LocalDateTime;

public class Roll {
    private int id;
    private LocalDateTime time;
    private int roll;
    private Coin coin;
    private boolean isBonusPot;
    private int multiplier;

    public Roll() {
    }

    public int getId() {
        return id;
    }

    public void setId(int id) {
        this.id = id;
    }

    public LocalDateTime getTime() {
        return time;
    }

    public void setTime(LocalDateTime time) {
        this.time = time;
    }

    public int getRoll() {
        return roll;
    }

    public void setRoll(int roll) {
        this.roll = roll;
    }

    public Coin getCoin() {
        return coin;
    }

    public void setCoin(Coin coin) {
        this.coin = coin;
    }

    public boolean isBonusPot() {
        return isBonusPot;
    }

    public void setBonusPot(boolean isBonusPot) {
        this.isBonusPot = isBonusPot;
    }

    public int getMultiplier() {
        return multiplier;
    }

    public void setMultiplier(int multiplier) {
        this.multiplier = multiplier;
    }

}
