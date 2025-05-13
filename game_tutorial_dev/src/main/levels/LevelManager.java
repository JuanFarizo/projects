package main.levels;

import java.awt.Graphics;
import java.awt.image.BufferedImage;
import main.Game;
import main.utils.LoadSave;

import static main.Game.TILES_SIZE;
import static main.utils.LoadSave.LEVEL_ATLAS;
import static main.utils.LoadSave.getSpriteAtlas;

public class LevelManager {
    private Game game;
    private BufferedImage[] levelSprite;
    private Level levelOne;

    public LevelManager(Game game) {
        this.game = game;
        importOutsideSprites();
        levelOne = new Level(LoadSave.getLevelData());
    }

    /**
     * Load the entire level into an array
     * */
    private void importOutsideSprites() {
        // 12 * 4 = 48
        BufferedImage img = getSpriteAtlas(LEVEL_ATLAS);
        levelSprite = new BufferedImage[48];
        for (int j = 0; j < 4; j++) {
            for (int i = 0; i < 12; i++) {
                int index = j * 12 + i;
                levelSprite[index] = img.getSubimage(i * 32, j * 32, 32, 32);
            }
        }
    }

    public void draw(Graphics g) {
        for (int j = 0; j < Game.TILES_IN_HEIGHT; j++) {
            for (int i = 0; i < Game.TILES_IN_WIDTH; i++) {
                int index = levelOne.getSpriteIndex(i, j);
                g.drawImage(levelSprite[index], i * TILES_SIZE, j* TILES_SIZE, TILES_SIZE, TILES_SIZE, null);
            }
        }
    }

    public void update() {

    }
}
