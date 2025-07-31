package udp_client;

import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;

public class UDPClient {
    public static void main(String[] args) {
        try {
            InetAddress serverAddress = InetAddress.getByName("localhost");
            int port = 9090;
            DatagramSocket clientSocket = new DatagramSocket(0);
            clientSocket.setSoTimeout(5000);
            //Amount of data = 65535 - 20 (IP Header) - 8 (UDP Header) = 65508
            byte[] sendData = new byte[1024];
            byte[] receiveData = new byte[1024];
            String stringSendData = "Hello Server!";
            sendData = stringSendData.getBytes();
            DatagramPacket sendPacket = new DatagramPacket(sendData, sendData.length, serverAddress, port);
            clientSocket.send(sendPacket);
            DatagramPacket receivePacket = new DatagramPacket(receiveData, receiveData.length);
            clientSocket.receive(receivePacket);
            receiveData = receivePacket.getData();
            String stringReceiveData = new String(receiveData);
            System.out.println("FROM SERVER: " + stringReceiveData);
            clientSocket.close();
        } catch (Exception e) {
            System.out.println(e.toString());
        }
    }
}
