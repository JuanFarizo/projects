package dynamic_proxy_reflec.external;

public interface DatabaseReader {
    int countRowInTable(String tableName) throws InterruptedException;
    String[] readRow(String query) throws InterruptedException;
}
