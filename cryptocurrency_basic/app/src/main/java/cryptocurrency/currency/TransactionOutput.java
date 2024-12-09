package cryptocurrency.currency;

import java.security.PublicKey;

public class TransactionOutput {
    // SHA-256
    private String id;
    // transaction id of the parent
    private String parentTransactionId;
    // the new owner of the coin
    private PublicKey receiver;
    private double amount;

    public TransactionOutput(String parentTransactionId, PublicKey receiver, double amount) {
        this.parentTransactionId = parentTransactionId;
        this.receiver = receiver;
        this.amount = amount;
        generateId();
    }

    private void generateId() {
        this.id = CryptographyHelper.generateHash(receiver.toString() + Double.toString(amount) + parentTransactionId);
    }

    public boolean isMine(PublicKey publicKey) {
        return this.receiver == publicKey;
    }

    public String getId() {
        return id;
    }

    public String getParentTransactionId() {
        return parentTransactionId;
    }

    public PublicKey getReceiver() {
        return receiver;
    }

    public double getAmount() {
        return amount;
    }

    public void setParentTransactionId(String parentTransactionId) {
        this.parentTransactionId = parentTransactionId;
    }

    public void setReceiver(PublicKey receiver) {
        this.receiver = receiver;
    }

    public void setAmount(double amount) {
        this.amount = amount;
    }

}
