package main.entities;

import java.awt.Graphics;
import java.awt.image.BufferedImage;
import main.utils.LoadSave;

import static main.utils.Constants.PlayerConstants.ATTACK_1;
import static main.utils.Constants.PlayerConstants.IDLE;
import static main.utils.Constants.PlayerConstants.RUNNING;
import static main.utils.Constants.PlayerConstants.getSpriteAmount;
import static main.utils.LoadSave.PLAYER_ATLAS;

public class Player extends Entity {
    private BufferedImage[][] animations;
    private int aniTick, aniIndex, aniSpeed = 15;
    private int playerAction = IDLE;
    private boolean moving = false;
    private boolean left, up, right, down;
    private float playerSpeed = 2.0f;
    private boolean attacking = false;

    public Player(float x, float y) {
        super(x, y);
        loadAnimations();
    }

    private void setAnimation() {
        int startAni = playerAction;
        if(moving) playerAction = RUNNING;
        else playerAction = IDLE;
        if(attacking) playerAction = ATTACK_1;
        if(startAni != playerAction) {
            resetAniTick();
        }
    }

    private void resetAniTick() {
        aniTick = 0;
        aniIndex = 0;
    }

    /**
     *  By default, the player is not moving
     *  If there is a keypress and is not canceled
     *  by the opposite then it will move
     * */
    private void updatePos() {
        moving = false;
        if(left && !right) {
            x-=playerSpeed;
            moving = true;
        } else if(right && !left) {
            x+=playerSpeed;
            moving = true;
        }

        if(up && !down) {
            y-=playerSpeed;
            moving = true;
        } else if(down && !up) {
            y+=playerSpeed;
            moving = true;
        }
    }
    public void update() {
        this.updatePos();
        this.updateAnimationTick();
        this.setAnimation();
    }

    /**
     * Controls the animation speed
     * and support the animation transitions
     */
    private void updateAnimationTick() {
        aniTick++;
        if (aniTick >= aniSpeed) {
            aniTick = 0;
            aniIndex++;
            if(aniIndex >= getSpriteAmount(playerAction)) {
                aniIndex = 0;
                attacking = false;
            }
        }
    }

    public void render(Graphics g) {
        g.drawImage(animations[playerAction][aniIndex],
                (int)x, (int)y,
                64 * 2,
                40 * 2,
                null);
    }
    /**
     * Load all the animation from a sprite,
     * adding each chunk of an animation into an array
     */
    private void loadAnimations() {
        BufferedImage img = LoadSave.getSpriteAtlas(PLAYER_ATLAS);
        animations = new BufferedImage[9][6];
        for (int j = 0; j < animations.length; j++) {
            for (int i = 0; i < animations[j].length; i++) {
                animations[j][i] = img.getSubimage(i * 64,j * 40, 64, 40);
            }
        }
    }

    public boolean isLeft() {
        return left;
    }

    public void setLeft(boolean left) {
        this.left = left;
    }

    public boolean isUp() {
        return up;
    }

    public void setUp(boolean up) {
        this.up = up;
    }

    public boolean isRight() {
        return right;
    }

    public void setRight(boolean right) {
        this.right = right;
    }

    public boolean isDown() {
        return down;
    }

    public void setDown(boolean down) {
        this.down = down;
    }

    public void restDirBoolean() {
        left = right = down = up = false;
    }

    public void setAttacking(boolean attacking) {
        this.attacking = attacking;
    }
}
