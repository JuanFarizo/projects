package tcp.conn;

import tcp.conn.repository.ServerRepository;

// import tcp.conn.config.SQLiteConfig;

public class App {

    public static void main(String[] args) throws Exception 
    {
        ChatServer chatServer = new ChatServer();
        try {
            chatServer.startServer();
            ServerRepository.initDB();
        } catch (Exception e) {
            System.out.println("Error initializing the application" + e.getMessage());
            throw e;
        }
    }
}
