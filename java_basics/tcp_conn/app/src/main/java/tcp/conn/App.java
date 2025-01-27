package tcp.conn;

import java.io.IOException;

// import tcp.conn.config.SQLiteConfig;

public class App {
    public static void main(String[] args) throws IOException 
    {
        ChatServer chatServer = new ChatServer();
        // SQLiteConfig.connect();
        chatServer.startServer();
    }
}
