package tcp.conn.client;

import java.io.IOException;

public class App {

    public static void main(String[] args) throws IOException {
        TCPClient tcpClient = new TCPClient();
        tcpClient.connect();
    }
}
