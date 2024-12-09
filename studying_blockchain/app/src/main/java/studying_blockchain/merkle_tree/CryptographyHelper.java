package studying_blockchain.merkle_tree;

import java.security.MessageDigest;

public class CryptographyHelper {

    public static String hash(String data) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(data.getBytes("UTF-8"));
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < hash.length; i++) {
                String hexadecimal = Integer.toHexString(0xff & hash[i]);
                if (hexadecimal.length() == 1)
                    sb.append('0');
                sb.append(hexadecimal);
            }
            return sb.toString();
        } catch (Exception e) {
            e.printStackTrace();
        }
        return null;
    }
}
