package tcp.conn.client.util;

import java.io.BufferedReader;
import java.io.InputStreamReader;

public class Ping {

     public static void main(String[] args) throws Exception {
        String hostAdd = "google.com";
        Process p = new ProcessBuilder("ping", hostAdd).start();
        
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(p.getInputStream()));) {
            String commandOutPut;
            while ((commandOutPut = reader.readLine()) != null) {
                System.out.println(commandOutPut);
            }
        } catch (Exception e) {
            // TODO: handle exception
        }
     }
}
