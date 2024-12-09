package cryptocurrency.blockchain;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

import cryptocurrency.currency.TransactionOutput;

public class Blockchain {
    // This is the public ledger - everyone can access
    // All the blocks (previous transactions) on the blockchain
    public static ArrayList<Block> blockChain;
    public static Map<String, TransactionOutput> UTXOs;

    public Blockchain() {
        Blockchain.blockChain = new ArrayList<>();
        Blockchain.UTXOs = new HashMap<>();
    }

    public void addBlock(Block block) {
        Blockchain.blockChain.add(block);
    }

    public int size() {
        return Blockchain.blockChain.size();
    }

    @Override
    public String toString() {
        String blockChain = "";
        for (Block block : Blockchain.blockChain) {
            blockChain += block.toString();
        }
        return blockChain;
    }

}
