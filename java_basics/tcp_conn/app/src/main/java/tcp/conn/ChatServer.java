package tcp.conn;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.HashSet;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import tcp.conn.domain.User;

/**
 * TPC Chat Server
 */
public class ChatServer {
    private static final Logger LOGGER = LoggerFactory.getLogger(ChatServer.class); 

    private static final int PORT = 5051;
    private static Set<PrintWriter> clientWriters = new HashSet<>(50);

    public void startServer() 
    {
        try (ServerSocket server = new ServerSocket(PORT)) 
        {
            LOGGER.info("Chat Server Started on port {} and IP Address {}", PORT, server.getInetAddress());
            while (true) {
                Socket clienSocket = server.accept();
                LOGGER.info("Client connected: {}", clienSocket.getInetAddress());
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
                    for (PrintWriter writer : clientWriters) {
                        if(this.out != writer) {
                            writer.println(String.format("Server: User %s has connected to the chat room", this.user.getUsername()));
                        }
                    }
                }
                String message;
                while ((message = in.readLine()) != null) 
                {
                    LOGGER.info("User {} send {}", this.user.getUsername(), message);
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
                LOGGER.error("Connection error: ", e.getMessage());
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
                LOGGER.info("User {} has disconnected", this.user.getUsername());
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
