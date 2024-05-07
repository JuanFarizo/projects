package org.example.template_method;

abstract class GameTM {
    protected int currentPlayer;
    protected final int numberOfPlayer;

    GameTM(int numberOfPlayer) {
        this.numberOfPlayer = numberOfPlayer;
    }

    public void run() {
        start();
        while(!haveWinner()) takeTurn();
        System.out.println("Player" + getWinningPlayer() + " wins");
    }

    protected abstract int getWinningPlayer();
    protected abstract void takeTurn();
    protected abstract boolean haveWinner();
    protected abstract void start();
}

class ChessTM extends GameTM {
    private int maxTurns = 10;
    private int turn = 1;

    public ChessTM() {
        super(2);
    }

    @Override
    protected int getWinningPlayer() {
        return 0;
    }

    @Override
    protected void takeTurn() {
        System.out.println("Turn " + (turn++) + " taken by player " + currentPlayer);
        currentPlayer = (currentPlayer + 1) % numberOfPlayer;
    }

    @Override
    protected boolean haveWinner() {
        return turn == maxTurns;
    }

    @Override
    protected void start() {
        System.out.println("Starting a game of chess.");
    }
}

public class TemplateMethodDemo {
    public static void main(String[] args) {
        new ChessTM().run();
    }
}
