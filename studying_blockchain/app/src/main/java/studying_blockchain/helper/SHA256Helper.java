package studying_blockchain.helper;

import java.security.MessageDigest;

public class SHA256Helper {
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
}
