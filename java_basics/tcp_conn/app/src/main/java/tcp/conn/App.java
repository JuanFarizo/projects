package tcp.conn;

import java.io.IOException;

public class App {
    public static void main(String[] args) throws IOException {
        ChatServer chatServer = new ChatServer();
        chatServer.startServer();
    }
}
