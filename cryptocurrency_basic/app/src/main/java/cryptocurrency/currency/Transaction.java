package cryptocurrency.currency;

import java.security.PrivateKey;
import java.security.PublicKey;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

import cryptocurrency.blockchain.Blockchain;

public class Transaction {

    // Id of the transaction is a 256-HASH
    private String transactionId;
    private PublicKey sender;
    private PublicKey receiver;
    private double amount;
    // The transaction is signed to prevent anyone else from spending the coins
    private byte[] signature;

    // every transaction has inputs and outputs
    public List<TransactionInput> inputs;
    public List<TransactionOutput> outputs;

    public Transaction(PublicKey sender, PublicKey receiver, double amount, List<TransactionInput> inputs) {
        this.outputs = new ArrayList<TransactionOutput>();
        this.sender = sender;
        this.receiver = receiver;
        this.amount = amount;
        this.inputs = inputs;
        calculateHash();
    }

    public boolean verifyTransaction() {
        if (!verifySignature()) {
            System.out.println("Invalid transaction because of invalid signature");
            return false;
        }

        // Using the unspent transactions
        inputs.forEach(t -> t.setUTXO(Blockchain.UTXOs.get(t.getTransactionOutputId())));
        // Transactions have 2 parts:
        // 1. Send an amount to the receiver
        // 2. Send the balance-amount back to the sender
        outputs.add(new TransactionOutput(this.transactionId, this.receiver, this.amount));
        outputs.add(new TransactionOutput(this.transactionId, this.sender, getInputsSum() - this.amount));

        // Update
        // The outputs will be inputs for other transactions
        // (we put them in blockchain UTXOs)
        outputs.forEach(t -> Blockchain.UTXOs.put(t.getId(), t));

        // Remove transactions inputs from blockchain's UTXOs list because they've been
        // spent
        inputs.stream()
                .filter(t -> Objects.nonNull(t.getUTXO()))
                .forEach(t -> Blockchain.UTXOs.remove(t.getUTXO().getId()));

        return true;
    }

    // Calculate how much money the sender has
    // Consider transaction in the past
    public double getInputsSum() {
        return inputs.stream()
                .filter(t -> Objects.nonNull(t.getUTXO()))
                .mapToDouble(t -> t.getUTXO().getAmount())
                .sum();
    }

    public boolean verifySignature() {
        String data = this.sender.toString() + this.receiver.toString() + Double.toString(this.amount);
        return CryptographyHelper.verify(this.sender, data, this.signature);
    }

    public void generateSignature(PrivateKey privateKey) {
        String data = this.sender.toString() + this.receiver.toString() + Double.toString(this.amount);
        this.signature = CryptographyHelper.sign(privateKey, data);
    }

    public void calculateHash() {
        String hashData = this.sender.toString() + this.receiver.toString() + Double.toString(this.amount);
        this.transactionId = CryptographyHelper.generateHash(hashData);
    }

    public String getTransactionId() {
        return this.transactionId;
    }

    public void setTransactionId(String transactionId) {
        this.transactionId = transactionId;
    }

    public PublicKey getSender() {
        return this.sender;
    }

    public void setSender(PublicKey sender) {
        this.sender = sender;
    }

    public PublicKey getReceiver() {
        return this.receiver;
    }

    public void setReceiver(PublicKey receiver) {
        this.receiver = receiver;
    }

    public double getAmount() {
        return this.amount;
    }

    public void setAmount(double amount) {
        this.amount = amount;
    }

    public byte[] getSignature() {
        return this.signature;
    }

    public void setSignature(byte[] signature) {
        this.signature = signature;
    }

    public List<TransactionInput> getInputs() {
        return this.inputs;
    }

    public void setInputs(List<TransactionInput> inputs) {
        this.inputs = inputs;
    }

    public List<TransactionOutput> getOutputs() {
        return this.outputs;
    }

    public void setOutputs(List<TransactionOutput> outputs) {
        this.outputs = outputs;
    }

}
