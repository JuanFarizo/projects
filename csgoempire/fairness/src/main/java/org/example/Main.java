package org.example;

import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.ObjectInputStream;
import java.security.MessageDigest;

public class Main {

    // $server_seed =
    // "96f3e04d221ca1b2048cc3b3b844e479f2bd9c80a870628072ee98fd1aa83cd0";
    // $public_seed = "460670512935";
    // $round = "321";
    // $hash = hash('sha256', $server_seed . "-" . $public_seed . "-" . $round);
    // $roll = hexdec(substr($hash, 0, 8)) % 15;
    // if ($roll == 0) $roll_colour = 'bonus';
    // elseif ($roll >= 1 and $roll <= 7) $roll_colour = 'orange';
    // elseif ($roll >= 8 and $roll <= 14) $roll_colour = 'black';
    //
    // echo("Roll: $roll\nColour: $roll_colour");
    //
    // Roll: 2
    // Colour: orange

    public final static String serverSeed = "eded67aa9831cc0560917f84a2ea0533fdaffe979ba89459244c47e28eb3d113";
    public final static String publicSeed = "1425231306";

    public static void main(String[] args) throws Exception {
        serializeData();


        String roundNumber = "9539247";
        MessageDigest md = MessageDigest.getInstance("SHA-256");
        String sb = serverSeed + "-" + publicSeed + "-" + roundNumber;
        byte[] hash = md.digest(sb.getBytes());

        StringBuilder hexString = new StringBuilder();
        for (byte b : hash) {
            hexString.append(String.format("%02x", b));
        }

        System.out.println("Hexadecimal String: " + hexString);

        String substringHash = hexString.substring(0, 8);
        int roll = Integer.parseInt(substringHash, 16) % 15;

        System.out.println("Roll: " + roll);

        String color = "";
        if (roll == 0)
            color = "bonus";
        else if (roll >= 1 && roll <= 7) {
            color = "orange";
        } else if (roll >= 8) {
            color = "black";
        }

        System.out.println(color);
    }

    private static final String jsonPath = "history.json";

    public static void serializeData() throws Exception {
        try (FileInputStream fi = new FileInputStream(jsonPath);
                ObjectInputStream in = new ObjectInputStream(fi);) {
            in.readObject();
        }
       
    }
}