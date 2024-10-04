package dynamic_proxy_reflec.external.impl;

import dynamic_proxy_reflec.external.DatabaseReader;

public class DatabaseReaderImpl implements DatabaseReader {

    @Override
    public int countRowInTable(String tableName) throws InterruptedException {
        System.out.println(String.format("DatabasReaderImpl - counting rows in table %s", tableName));
        Thread.sleep(1000);
        return 50;
    }

    @Override
    public String[] readRow(String query) throws InterruptedException {
        System.out.println(String.format("DatabaseReaderImpl - Execution the query : %s ", query));
        Thread.sleep(1500);
        return new String[]{"Column1", "Column2", "Column3"};
    }

}
