package main.input;

import java.awt.event.KeyEvent;
import java.awt.event.KeyListener;
import main.GamePanel;

public class KeyBoardInputs implements KeyListener {
    private GamePanel gamePanel;

    public KeyBoardInputs(GamePanel gamePanel) {
        this.gamePanel = gamePanel;
    }

    @Override
    public void keyTyped(KeyEvent e) {

    }

    @Override
    public void keyPressed(KeyEvent e) {
        switch (e.getKeyCode()) {
            case KeyEvent.VK_W -> this.gamePanel.getGame().getPlayer().setUp(true);
            case KeyEvent.VK_A -> this.gamePanel.getGame().getPlayer().setLeft(true);
            case KeyEvent.VK_S -> this.gamePanel.getGame().getPlayer().setDown(true);
            case KeyEvent.VK_D -> this.gamePanel.getGame().getPlayer().setRight(true);
        }
    }

    @Override
    public void keyReleased(KeyEvent e) {
        switch (e.getKeyCode()) {
            case KeyEvent.VK_W -> this.gamePanel.getGame().getPlayer().setUp(false);
            case KeyEvent.VK_A -> this.gamePanel.getGame().getPlayer().setLeft(false);
            case KeyEvent.VK_S -> this.gamePanel.getGame().getPlayer().setDown(false);
            case KeyEvent.VK_D -> this.gamePanel.getGame().getPlayer().setRight(false);
        }
    }
}
