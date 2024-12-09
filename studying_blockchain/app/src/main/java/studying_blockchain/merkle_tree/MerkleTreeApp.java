package studying_blockchain.merkle_tree;

import java.util.ArrayList;
import java.util.List;

public class MerkleTreeApp {
    /**
     * Why to use Merkle Trees?
     * --> Because we can represent all the transactions within a block by a single
     * hash
     * --> This single hash is in the header of the block in the blockchain (so it
     * is a memory efficient solution)
     * --> This is the merkle root: we recursively keep hashing the leaf nodes in
     * the tree-like structure
     * THE ROOT CAN VERIFY THAT ALL THE TRANSACTIONS ARE VALID IN THE BLOCK
     */
    public static void main(String[] args) {
        List<String> transactions = new ArrayList<>();

        transactions.add("aa");
        transactions.add("bb");
        transactions.add("dd");
        MerkleTree merkleTree = new MerkleTree(transactions);
        System.out.println(merkleTree.getMerkleRoot());
    }
}
