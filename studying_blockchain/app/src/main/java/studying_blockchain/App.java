package studying_blockchain;

public class App {
    public static void main(String[] args) {
        BlockChain blockChain = new BlockChain();
        Miner miner = new Miner();

        // Genesis Block
        Block block0 = new Block(0, "", Constants.GENESIS_PREV_HASH);
        miner.mine(block0, blockChain);

        Block block1 = new Block(1, "transaction1", blockChain.getBlockChain().get(blockChain.getSize() - 1).getHash());
        miner.mine(block1, blockChain);

        Block block2 = new Block(2, "transaction1", blockChain.getBlockChain().get(blockChain.getSize() - 1).getHash());
        miner.mine(block2, blockChain);

        System.lineSeparator();
        System.out.println("Blockchain: " + blockChain);
        System.out.println("Miner's reward: " + miner.getReward());

    }
}
