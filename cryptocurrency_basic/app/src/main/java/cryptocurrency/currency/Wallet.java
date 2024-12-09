package cryptocurrency.currency;

import java.security.KeyPair;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.util.ArrayList;
import java.util.List;

import cryptocurrency.blockchain.Blockchain;

public class Wallet {
    // User's of the network
    // Used for signature
    private PrivateKey privateKey;
    // Used for verification
    private PublicKey publicKey; // (Address: RIPMD Point in the elliptic curve (160bits))

    public Wallet() {
        KeyPair keyPair = CryptographyHelper.ellipticCurveCrypto();
        this.privateKey = keyPair.getPrivate();
        this.publicKey = keyPair.getPublic();
    }

    // Miners will put this transaction into the blockchain
    public Transaction transferMoney(PublicKey receiver, double amount) {
        if (calculateBalance() < amount) {
            System.out.println(" Invalid transaction because of not enough money");
            return null;
        }
        // Store the inputs for the transaction
        List<TransactionInput> inputs = new ArrayList<>();

        Blockchain.UTXOs.entrySet().stream().map(item -> item.getValue())
                .filter(tranOutput -> tranOutput.isMine(this.publicKey))
                .forEach(tranOutput -> inputs.add(new TransactionInput(tranOutput.getId())));

        Transaction newTransaction = new Transaction(this.publicKey, receiver, amount, inputs);
        newTransaction.generateSignature(privateKey);
        return newTransaction;
    }

    // There is no balance associated with the users
    // UTXOs and consider all transaction in the past
    public double calculateBalance() {
        return Blockchain.UTXOs.entrySet().stream()
                .map(item -> item.getValue())
                .filter(tranOutput -> tranOutput.isMine(this.publicKey))
                .mapToDouble(tranOutput -> tranOutput.getAmount()).sum();
    }

    public PrivateKey getPrivateKey() {
        return privateKey;
    }

    public PublicKey getPublicKey() {
        return publicKey;
    }

}
