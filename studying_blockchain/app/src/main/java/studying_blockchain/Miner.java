package studying_blockchain;

public class Miner {
    private double reward;

    public void mine(Block block, BlockChain blockChain) {
        while (!isGoldenHash(block)) {
            block.incrementNonce();
            block.generateHash();
        }

        System.out.println(block + " hash just mined...");
        System.out.println("Hash is: " + block.getHash());
        blockChain.addBlock(block);
        this.reward += Constants.REWARD;
    }

    private boolean isGoldenHash(Block block) {
        // Create the string with same quantity of 0 than difficulty
        String leadingZeros = new String(new char[Constants.DIFFICULTY]).replace('\0', '0');
        return block.getHash().subSequence(0, Constants.DIFFICULTY).equals(leadingZeros);
    }

    public double getReward() {
        return reward;
    }

}
