package tcp.conn.repository;

import java.sql.Connection;
import java.sql.SQLException;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import tcp.conn.config.DataSourceConfig;

public class ServerRepository 
{
    private static final Logger LOGGER = LoggerFactory.getLogger(ServerRepository.class); 
    public static void initDB() throws Exception
    {
        try (Connection conn = DataSourceConfig.getConnection()) 
        {
            LOGGER.info("Connection to SQLite has been established.");
            createTables(conn);
            LOGGER.info("Tables create successfully");
        }
        catch (Exception e) 
        {
            LOGGER.error("Exception durin the table creation {}", e.getMessage());
            throw e;
        }
    }

    private static void createTables(Connection conn) throws SQLException
    {
        String userSchema = """
                CREATE TABLE IF NOT EXISTS users (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    username text NOT NULL,
                    address text NOT NULL
                );
                """;
        
        String messageSchema = """
                CREATE TABLE IF NOT EXISTS messages (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    sender INTEGER NOT NULL,
                    receiver INTEGER NOT NULL,
                    message text NOT NULL,
                    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
                    FOREIGN KEY (sender) REFERENCES users(id),
                    FOREIGN KEY (receiver) REFERENCES users(id)
                );
                """;

        String lastSeenSchema = """
                CREATE TABLE IF NOT EXISTS last_seen (
                    user_id INTEGER NOT NULL,
                    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
                    FOREIGN KEY (user_id) REFERENCES users(id)
                );
                """;
        
        String groupSchema = """
                CREATE TABLE IF NOT EXIST group (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    group_id INTEGER NOT NULL,
                    user_id INTEGER NOT NULL,
                    FOREIGN KEY (user_id) REFERENCES users(id)
                );
                """;
       
        conn.createStatement().execute(userSchema);
        LOGGER.info("User table created");

        conn.createStatement().execute(messageSchema);
        LOGGER.info("Message table created");
        conn.createStatement().execute(lastSeenSchema);
        LOGGER.info("Last seen table created");
    }
}
