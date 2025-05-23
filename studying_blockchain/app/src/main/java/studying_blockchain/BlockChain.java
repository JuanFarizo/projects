package studying_blockchain;

import java.util.LinkedList;
import java.util.List;

public class BlockChain {
    // immutable ledger (we can't remove blocks)
    private List<Block> blockChain;

    public BlockChain() {
        this.blockChain = new LinkedList<>();
    }

    public void addBlock(Block block) {
        this.blockChain.add(block);
    }

    public List<Block> getBlockChain() {
        return this.blockChain;
    }

    public int getSize() {
        return this.blockChain.size();
    }

    @Override
    public String toString() {
        String s = "";
        for (Block block : blockChain) {
            s += block.toString() + System.lineSeparator();
        }
        return s;
    }

}
