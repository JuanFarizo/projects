package tcp.conn.client;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.net.Socket;

public class TCPClient 
{
    private static final int PORT = 5051;
    private static final String IP_ADDRESS = "127.0.0.1";

    public void connect() throws IOException
    {
        try (Socket socket = new Socket(IP_ADDRESS, PORT);
            BufferedReader in = new BufferedReader(new InputStreamReader(socket.getInputStream()));
            PrintWriter out = new PrintWriter(socket.getOutputStream(), true);
            BufferedReader console = new BufferedReader(new InputStreamReader(System.in))) 
        {
            System.out.println("Connected to chat server");
            Thread listener = new Thread(() ->
            {
                try
                {
                    String serverMessage;
                    while ((serverMessage = in.readLine()) != null) 
                    {
                        System.out.println(serverMessage);
                    }
                } 
                catch (IOException e)
                {
                    System.out.println("Disconnected from server.");
                }
            });
            listener.start();

            String userInput;
            while ((userInput = console.readLine()) != null) 
            {
                out.println(userInput);
            }
        } 
        catch (Exception e) 
        {
            e.printStackTrace();
        }
    }
}
