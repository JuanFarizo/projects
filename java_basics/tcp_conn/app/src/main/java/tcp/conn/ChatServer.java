package tcp.conn;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.HashSet;
import java.util.Set;

import tcp.conn.domain.User;

/**
 * TPC Chat Server
 */
public class ChatServer {
    private static final int PORT = 5051;
    private static Set<PrintWriter> clientWriters = new HashSet<>();

    public void startServer() 
    {
        try (ServerSocket server = new ServerSocket(PORT)) 
        {
            System.out.println("Chat Server Started on port " + PORT + " and IP Address " + server.getInetAddress());
            System.out.println("Waiting for clients to connect...");
            while (true) {
                Socket clienSocket = server.accept();
                System.out.println("Client connected: " + clienSocket.getInetAddress());
                new ClientHandler(clienSocket).start();
            }
        } 
        catch (Exception e) 
        {
            e.printStackTrace();
        }
    }

    class ClientHandler extends Thread 
    {
        private Socket socket;
        private PrintWriter out;
        private User user;

        public ClientHandler(Socket socket) 
        {
            this.socket = socket;
        }

        public void run()
        {
            try (BufferedReader in = new BufferedReader(new InputStreamReader(socket.getInputStream()))) 
            {
                out = new PrintWriter(socket.getOutputStream(), true);
                out.println("Welcome to the chat server. Please enter your username: ");
                if(in.readLine() != null) {
                    this.user = new User(in.readLine(), socket.getInetAddress().toString());
                }
                synchronized (clientWriters) 
                {
                    clientWriters.add(out);
                }
                String message;
                while ((message = in.readLine()) != null) 
                {
                    System.out.println("Received: " + message);
                    synchronized (clientWriters) 
                    {
                        for (PrintWriter writer : clientWriters) 
                        {
                            if(this.out != writer)
                            {
                                writer.println(this.user.getUsername() + ": " + message);
                            }
                        }
                    }
                }
            } 
            catch (IOException e) 
            {
                System.out.println("Connection error: " + e.getMessage());
            } 
            finally 
            {
                synchronized (clientWriters) 
                {
                    clientWriters.remove(out);
                }
            }
            try 
            {
                socket.close();
            } 
            catch (Exception e) 
            {
                e.printStackTrace();
            }
        }


        private void logInUser() {
            
        }
    }
}
