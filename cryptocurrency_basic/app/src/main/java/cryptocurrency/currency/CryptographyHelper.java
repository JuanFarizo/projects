package cryptocurrency.currency;

import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.Signature;
import java.security.spec.ECGenParameterSpec;

public class CryptographyHelper {
    // Generate public and private key
    // private key: 256 bit long random integer
    // public key: point on the elliptic curve (x, y) both values are 256 bit long
    public static KeyPair ellipticCurveCrypto() {
        try {
            KeyPairGenerator keyPairGenerator = KeyPairGenerator.getInstance("ECDSA", "BC");
            ECGenParameterSpec params = new ECGenParameterSpec("prime256v1");
            keyPairGenerator.initialize(params);
            return keyPairGenerator.generateKeyPair();
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    public static String generateHash(String data) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(data.getBytes("UTF-8"));
            StringBuilder hexadecimalString = new StringBuilder();
            for (int i = 0; i < hash.length; i++) {
                // 0xff & --> Make sure there are not negative values
                String hexadecimal = Integer.toHexString(0xff & hash[i]);
                // Padding to ensure the 64 characters
                if (hexadecimal.length() == 1)
                    hexadecimalString.append('0');
                hexadecimalString.append(hexadecimal);
            }
            return hexadecimalString.toString();
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    // Elliptic Curve Digital Signature Algorithm
    public static byte[] sign(PrivateKey privateKey, String input) {
        Signature signature;
        byte[] output = new byte[0];
        try {
            // Use bouncy castle for ecc
            signature = Signature.getInstance("ECDSA", "BC");
            signature.initSign(privateKey);
            signature.update(input.getBytes());
            output = signature.sign();
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
        return output;
    }

    // Check transaction belongs to the sender based on the signature
    public static boolean verify(PublicKey publicKey, String data, byte[] signature) {
        try {
            Signature ecdsaSignature = Signature.getInstance("ECDSA", "BC");
            ecdsaSignature.initVerify(publicKey);
            ecdsaSignature.update(data.getBytes());
            return ecdsaSignature.verify(signature);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }
}
