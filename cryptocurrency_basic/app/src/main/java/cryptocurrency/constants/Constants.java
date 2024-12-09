package cryptocurrency.constants;

public class Constants {
    private Constants() {
    }

    // the number of leading zeros
    public static final int DIFFICULTY = 5;
    // first block (genesis) the hash SHA-256 first block
    public static final String GENESIS_PREV_HASH = "0000000000000000000000000000000000000000000000000000000000000000";
    public static final double MINER_REWARD = 6.25;
}
