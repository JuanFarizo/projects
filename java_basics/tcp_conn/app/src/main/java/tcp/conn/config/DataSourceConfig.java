package tcp.conn.config;

import java.sql.Connection;
import java.sql.SQLException;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;

public class DataSourceConfig {
    private static HikariDataSource dataSource;

    static 
    {
        HikariConfig config = new HikariConfig();
        config.setJdbcUrl("jdbc:sqlite:chat_server.db");
        config.setDriverClassName("org.sqlite.JDBC");
        config.setMaximumPoolSize(10); 
        config.setMinimumIdle(2);
        config.setIdleTimeout(30000); 
        config.setConnectionTimeout(30000); 
        config.setConnectionTestQuery("SELECT 1");
        dataSource = new HikariDataSource(config);
    }

    private DataSourceConfig() {}

    public  static Connection getConnection() throws SQLException 
    {
        return dataSource.getConnection();
    }

    public static void close() 
    {
        dataSource.close();
    }

}