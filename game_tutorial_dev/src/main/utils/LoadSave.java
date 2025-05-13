package main.utils;

import java.awt.Color;
import java.awt.image.BufferedImage;
import java.io.IOException;
import java.io.InputStream;

import javax.imageio.ImageIO;

import static main.Game.TILES_IN_HEIGHT;
import static main.Game.TILES_IN_WIDTH;

public class LoadSave {
    public static final String PLAYER_ATLAS = "player_sprites.png";
    public static final String LEVEL_ATLAS = "outside_sprites.png";
    public static final String LEVEL_ONE_DATA = "level_one_data.png";
    /**
     * Import an image into the project
     * @return BufferedImage importedImage
     */
     public static BufferedImage getSpriteAtlas(String path) {
         try (InputStream is = LoadSave.class.getResourceAsStream("/" + path )){
             return  ImageIO.read(is);
         } catch (IOException e) {
             throw new RuntimeException(e);
         }
     }

     public static int[][] getLevelData() {
         int[][] lvlData = new int[TILES_IN_HEIGHT][TILES_IN_WIDTH];
         BufferedImage img = getSpriteAtlas(LEVEL_ONE_DATA);
         for (int j = 0; j < img.getHeight(); j++) {
             for (int i = 0; i < img.getWidth(); i++) {
                 Color color = new Color(img.getRGB(i, j));
                 int value = color.getRed();
                 if (value >= 48) value = 0;
                 lvlData[j][i] = value;
             }
         }
         return lvlData;
     }
}
