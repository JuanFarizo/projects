package cryptocurrency.blockchain;

import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Objects;

import cryptocurrency.constants.Constants;
import cryptocurrency.currency.CryptographyHelper;
import cryptocurrency.currency.Transaction;

public class Block {
    private int id;
    private int nonce;
    private long timeStamp;
    private String hash;
    private String previousHash;
    public List<Transaction> transactions;

    public Block(String previousHash) {
        this.transactions = new ArrayList<>();
        this.previousHash = previousHash;
        this.timeStamp = new Date().getTime();
        generateHash();
    }

    public void generateHash() {
        String dataToHash = Integer.toString(id) +
                previousHash +
                Long.toString(timeStamp)
                + transactions.toString() +
                Integer.toString(nonce);
        this.hash = CryptographyHelper.generateHash(dataToHash);
    }

    public boolean addTransaction(Transaction transaction) {
        if (Objects.isNull(transaction))
            return false;

        if (!previousHash.equals(Constants.GENESIS_PREV_HASH) &&
                !transaction.verifyTransaction()) {
            return false;
        }

        return transactions.add(transaction);
    }

    public void incrementNonce() {
        this.nonce++;
    }

    public String getHash() {
        return hash;
    }

}
