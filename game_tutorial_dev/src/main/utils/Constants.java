package main.utils;

public class Constants {

    public static class PlayerConstants {
        public static final int IDLE = 0;
        public static final int RUNNING = 1;
        public static final int JUMPING = 2;
        public static final int FALLING = 3;
        public static final int GROUND = 4;
        public static final int HIT = 5;
        public static final int ATTACK_1 = 6;
        public static final int ATTACK_JUMP_1 = 7;
        public static final int ATTACK_JUMP_2 = 8;

        public static int getSpriteAmount(int playerAction) {
            switch (playerAction) {
                case RUNNING -> {return 6;}
                case IDLE -> {return 5;}
                case HIT -> {return 4;}
                case JUMPING,
                     ATTACK_1,
                     ATTACK_JUMP_1,
                     ATTACK_JUMP_2 -> {return 3;}
                case GROUND -> {return 2;}
                default -> {return 1;}
            }
        }
    }

    public static class Directions {
        public static final int LEFT = 0;
        public static final int UP = 1;
        public static final int RIGHT = 2;
        public static final int DOWN = 3;
    }
}
