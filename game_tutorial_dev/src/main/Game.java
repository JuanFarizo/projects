package main;

import java.awt.Graphics;
import main.entities.Player;
import main.levels.LevelManager;

public class Game implements Runnable {
    public final static int TILES_DEFAULT_SIZE = 32;
    public final static float SCALE = 1.5f;
    public final static int TILES_IN_WIDTH = 26;
    public final static int TILES_IN_HEIGHT = 14;
    public final static int TILES_SIZE = (int) (TILES_DEFAULT_SIZE * SCALE);
    public final static int GAME_WIDTH = TILES_SIZE * TILES_IN_WIDTH;
    public final static int GAME_HEIGHT = TILES_SIZE * TILES_IN_HEIGHT;


    private final GameWindow gameWindow;
    private final GamePanel gamePanel;
    private Thread gameThread;
    private final int FPS_SET = 120;
    private final int UPS_SET = 200;
    private Player player;
    private LevelManager levelManager;

    public Game() {
        initClasses();
        this.gamePanel = new GamePanel(this);
        this.gameWindow = new GameWindow(gamePanel);
        this.gamePanel.requestFocus();
        this.startGameLoop();
    }

    private void initClasses() {
        player = new Player(200, 200);
        levelManager = new LevelManager(this);
    }

    private void startGameLoop() {
        gameThread = new Thread(this);
        gameThread.start();
    }

    public void update() {
        player.update();
        levelManager.update();
    }

    public void render(Graphics g) {
        player.render(g);
        levelManager.draw(g);
    }

    public Player getPlayer() {
        return player;
    }

    @Override
    public void run() {
        double timePerFrame = 1_000_000_000.0 / FPS_SET;
        double timePerUpdate = 1_000_000_000.0 / UPS_SET;
        int frames = 0;
        int updates = 0;
        long lastCheck = System.currentTimeMillis();
        long previousTime = System.nanoTime();
        double deltaU = 0;
        double deltaF = 0;
        while(true) {
            long currenTime = System.nanoTime();
            deltaU += (currenTime - previousTime) / timePerUpdate;
            deltaF += (currenTime - lastCheck) / timePerFrame;
            previousTime = currenTime;
            if(deltaU >= 1) {
                update();
                updates++;
                deltaU--;
            }
            if(deltaF >= 1) {
                gamePanel.repaint();
                frames++;
                deltaF--;
            }
            if (System.currentTimeMillis() - lastCheck >= 1000) {
                lastCheck = System.currentTimeMillis();
                System.out.println("FPS: " + frames + " | UPS: " + updates);
                frames = 0;
                updates = 0;
            }
        }
    }

    public void windowFocusLost() {
        player.restDirBoolean();
    }
}
