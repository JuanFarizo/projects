package cryptocurrency.currency;

import cryptocurrency.blockchain.Block;
import cryptocurrency.blockchain.Blockchain;
import cryptocurrency.constants.Constants;

public class Miner {
    private double reward;

    public void mine(Block block, Blockchain blockchain) {
        while (!isGoldenHash(block)) {
            // This is the PoW
            block.incrementNonce();
            block.generateHash();
        }
    }

    public boolean isGoldenHash(Block block) {
        String leadingZeros = new String(new char[Constants.DIFFICULTY]).replace('\0', '0');
        return block.getHash().substring(0, Constants.DIFFICULTY).equals(leadingZeros);
    }

    public double getReward() {
        return reward;
    }

}
