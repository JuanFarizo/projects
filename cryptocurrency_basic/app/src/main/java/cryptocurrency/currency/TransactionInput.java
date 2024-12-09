package cryptocurrency.currency;

public class TransactionInput {
    // Every input has an output
    private String transactionOutputId;
    // The unspent transaction output
    private TransactionOutput UTXO;

    public TransactionInput(String transactionOutputId) {
        this.transactionOutputId = transactionOutputId;
    }

    public String getTransactionOutputId() {
        return transactionOutputId;
    }

    public void setTransactionOutputId(String transactionOutputId) {
        this.transactionOutputId = transactionOutputId;
    }

    public TransactionOutput getUTXO() {
        return this.UTXO;
    }

    public void setUTXO(TransactionOutput uTXO) {
        this.UTXO = uTXO;
    }

}
