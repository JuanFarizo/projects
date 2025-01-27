package tcp.conn;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.HashSet;
import java.util.Set;

/**
 * TPC Chat Server
 */
public class ChatServer {
    private static final int PORT = 5051;
    private static Set<PrintWriter> clientWriters = new HashSet<>();

    public void startServer() 
    {
        System.out.println("Chat Server Started");
        try (ServerSocket server = new ServerSocket(PORT)) 
        {
            while (true) {
                new ClientHandler(server.accept()).start();
            }
        } 
        catch (Exception e) 
        {
            e.printStackTrace();
        }
    }

    class ClientHandler extends Thread {
        private Socket socket;
        private PrintWriter out;

        public ClientHandler(Socket socket) {
            this.socket = socket;
        }

        public void run() {
            try (BufferedReader in = new BufferedReader(new InputStreamReader(socket.getInputStream()))) {
                out = new PrintWriter(socket.getOutputStream(), true);
                synchronized (clientWriters) {
                    clientWriters.add(out);
                }
                String message;
                while ((message = in.readLine()) != null) {
                    System.out.println("Received: " + message);
                    synchronized (clientWriters) {
                        for (PrintWriter writer : clientWriters) {
                            writer.println(message);
                        }
                    }
                }
            } catch (IOException e) {
                System.out.println("Connection error: " + e.getMessage());
            } finally {
                synchronized (clientWriters) {
                    clientWriters.remove(out);
                }
            }
            try {
                socket.close();
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }
}
