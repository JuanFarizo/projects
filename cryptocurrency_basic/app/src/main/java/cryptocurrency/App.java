package cryptocurrency;

import java.security.Security;

import org.bouncycastle.jce.provider.BouncyCastleProvider;

import cryptocurrency.blockchain.Block;
import cryptocurrency.blockchain.Blockchain;
import cryptocurrency.constants.Constants;
import cryptocurrency.currency.Miner;
import cryptocurrency.currency.Transaction;
import cryptocurrency.currency.TransactionOutput;
import cryptocurrency.currency.Wallet;

public class App {
    public String getGreeting() {
        return "Hello World!";
    }

    public static void main(String[] args) {
        // Bouncy castle as the cryptography provider
        Security.addProvider(new BouncyCastleProvider());

        Wallet userA = new Wallet();
        Wallet userB = new Wallet();
        Wallet lender = new Wallet();
        Blockchain blockchain = new Blockchain();
        Miner miner = new Miner();

        // Create genesis transaction that send 500 coins to user A
        Transaction genesisTransaction = new Transaction(lender.getPublicKey(), userA.getPublicKey(), 500, null);
        genesisTransaction.generateSignature(lender.getPrivateKey());
        genesisTransaction.setTransactionId("0");
        genesisTransaction.outputs.add(new TransactionOutput(genesisTransaction.getTransactionId(),
                genesisTransaction.getReceiver(), genesisTransaction.getAmount()));
        Blockchain.UTXOs.put(genesisTransaction.getOutputs().get(0).getId(), genesisTransaction.getOutputs().get(0));

        System.out.println("Constructing the genesis block...");
        Block genesis = new Block(Constants.GENESIS_PREV_HASH);
        genesis.addTransaction(genesisTransaction);
        miner.mine(genesis, blockchain);

        Block block1 = new Block(genesis.getHash());
        System.out.println("User A balance is: " + userA.calculateBalance());
        System.out.println("User tries to send money (120 cons to user B)");
        block1.addTransaction(userA.transferMoney(userB.getPublicKey(), 120));
        miner.mine(block1, blockchain);
        System.out.println("User A balance is: " + userA.calculateBalance());
        System.out.println("User B balance is: " + userB.calculateBalance());

        Block block2 = new Block(block1.getHash());
        System.out.println("User sends more 600 than it has");
        block2.addTransaction(userA.transferMoney(userB.getPublicKey(), 600));
        miner.mine(block2, blockchain);
        System.out.println("User A balance is: " + userA.calculateBalance());
        System.out.println("User B balance is: " + userB.calculateBalance());

        Block block3 = new Block(block2.getHash());
        System.out.println("User B send founds 110 to user A");
        block3.addTransaction(userB.transferMoney(userA.getPublicKey(), 110));
        System.out.println("User A balance is: " + userA.calculateBalance());
        System.out.println("User B balance is: " + userB.calculateBalance());
        miner.mine(block3, blockchain);

        System.out.println("Miner's reward " + miner.getReward());
    }
}
