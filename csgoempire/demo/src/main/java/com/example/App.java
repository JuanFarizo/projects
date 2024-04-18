package com.example;

/**
 * Hello world!
 *
 */
public class App {

    public static final String serverSeed = "77c2e9b54af932b03b3ac077a350c8acfd9974ae46ae7d2835482ff05a9adae8";
    public static final long publicSeed = 1425231306;

    public int roll;
    
    // $server_seed =
    // "96f3e04d221ca1b2048cc3b3b844e479f2bd9c80a870628072ee98fd1aa83cd0";
    // $public_seed = "460670512935";
    // $round = "321";
    // $hash = hash('sha256', $server_seed . "-" . $public_seed . "-" . $round);
    // $roll = hexdec(substr($hash, 0, 8)) % 15;
    // if ($roll == 0) $roll_colour = 'bonus';
    // elseif ($roll >= 1 and $roll <= 7) $roll_colour = 'orange';
    // elseif ($roll >= 8 and $roll <= 14) $roll_colour = 'black';

    // echo("Roll: $roll\nColour: $roll_colour");

    public static void main(String[] args) {
        System.out.println("Hello World!");
    }
}
