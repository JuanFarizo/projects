package studying_blockchain.ecc;

import java.util.Random;

public class App {
    public static void main(String[] args) {
        ECC ecc = new ECC(0, 7);
        Point generator = new Point(-2, 1);
        Random random = new Random();
        // Elliptic Curve Diffie-Hellman algorithm
        int a = random.nextInt(10000);
        int b = random.nextInt(10000);

        // Public keys with the double and add algorithm
        // these are points on the elliptic curve
        Point aPublicKey = ecc.doubleAndAdd(a, generator);
        Point bPublicKey = ecc.doubleAndAdd(b, generator);

        // They can generate the same private key they can use for symmetric encryption
        Point aSecretKey = ecc.doubleAndAdd(a, bPublicKey);
        Point bSecretKey = ecc.doubleAndAdd(b, aPublicKey);

        System.out.println(aSecretKey);
        System.out.println(bSecretKey);
    }
}
