package tcp.conn.config;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;

public class SQLiteConfig 
{

    private final static String url = "jdbc:sqlite:chat_server.db";

    public static void connect()
    {
        try (Connection conn = DriverManager.getConnection(url)) 
        {
            System.out.println("Connection to SQLite has been established.");
            createTables(conn);
        } 
        catch (Exception e) 
        {
            System.out.println(e.getMessage());
        }
    }

    private static void createTables(Connection conn) throws SQLException
    {
        String userStatement = "CREATE TABLE IF NOT EXISTS users (\n"
                + " id text PRIMARY KEY,\n"
                + " username text NOT NULL,\n"
                + " address text NOT NULL\n"
                + ");";
        
        String messageStatement = "CREATE TABLE IF NOT EXISTS messages (\n"
                + " id integer PRIMARY KEY,\n"
                + " sender text NOT NULL,\n"
                + " receiver text NOT NULL,\n"
                + " message text NOT NULL,\n"
                + " timestamp text NOT NULL\n"
                + ");";
       
        conn.createStatement().execute(userStatement);
        conn.createStatement().execute(messageStatement);
    }
}
