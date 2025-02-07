package tcp.conn.repository;

import java.sql.Connection;
import java.sql.SQLException;

import tcp.conn.config.DataSourceConfig;

public class ServerRepository 
{
    public static void initDB() throws Exception
    {
        try (Connection conn = DataSourceConfig.getConnection()) 
        {
            System.out.println("Connection to SQLite has been established.");
            createTables(conn);
        } 
        catch (Exception e) 
        {
            System.out.println(e.getMessage());
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
       
        boolean userResult = conn.createStatement().execute(userSchema);
        if(userResult) System.out.println("User table created");
        boolean messageResult = conn.createStatement().execute(messageSchema);
        if(messageResult) System.out.println("Message table created");
        boolean lastSeenResult = conn.createStatement().execute(lastSeenSchema);
        if(lastSeenResult) System.out.println("Last Seen table created");
    }
}
