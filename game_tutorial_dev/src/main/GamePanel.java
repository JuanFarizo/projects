package main;

import main.input.KeyBoardInputs;
import main.input.MouseInputs;
import java.awt.Dimension;
import java.awt.Graphics;

import javax.swing.JPanel;

import static main.Game.GAME_HEIGHT;
import static main.Game.GAME_WIDTH;

public class GamePanel extends JPanel {
    private final MouseInputs mouseInputs;
    private final Game game;
    public GamePanel(Game game) {
        this.mouseInputs = new MouseInputs(this);
        this.game = game;
        addKeyListener(new KeyBoardInputs(this));
        setPanelSize();
        addMouseListener(mouseInputs);
        addMouseMotionListener(mouseInputs);
    }

    public Game getGame() {
        return game;
    }

    public void updateGame() {

    }

    /***
     * Set the size of the panel with a
     * Dimension object
     */
    private void setPanelSize() {
        Dimension size = new Dimension(GAME_WIDTH, GAME_HEIGHT);
        setPreferredSize(size);
    }

    /**
     * Paint the images into the panel
     * @param g the <code>Graphics</code>
     */
    public void paintComponent(Graphics g) {
        super.paintComponent(g);
        game.render(g);
    }

}