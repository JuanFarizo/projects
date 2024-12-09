package studying_blockchain.merkle_tree;

import java.util.ArrayList;
import java.util.List;

public class MerkleTree {
    private List<String> transactions;

    public MerkleTree(List<String> transactions) {
        this.transactions = transactions;
    }

    // the root is in this list in the end
    public String getMerkleRoot() {
        return construct(this.transactions).get(0);
    }

    // Recursive fn that keeps merging the neighboring hashes (index i and i+1)
    private List<String> construct(List<String> transactions) {
        // Base case
        if (transactions.size() == 1)
            return transactions;

        List<String> updatedList = new ArrayList<>();
        for (int i = 0; i < transactions.size() - 1; i += 2) {
            updatedList.add(mergeHash(transactions.get(i), transactions.get(i + 1)));
        }
        // if the number of transactions is odd : the last item is hashed with itself
        if (transactions.size() % 2 == 1) {
            updatedList.add(
                    mergeHash(transactions.get(transactions.size() - 1), transactions.get(transactions.size() - 1)));
        }

        // recursive method call (tail recursion)
        return construct(updatedList);
    }

    // Concat two strings and hash it with SHA256
    private String mergeHash(String hash1, String hash2) {
        return CryptographyHelper.hash(hash1 + hash2);
    }
}
