package tcp.conn.client.util;

public class ValidateIP {
    public static void main(String[] args) {
        System.out.println(validateIpAddress("127.0.0.1"));
    }

    public static boolean validateIpAddress(String ipAddress) {
        String[] numbers = ipAddress.split("\\.");
        if(numbers.length != 4) return false;

        for (int i = 0; i < numbers.length; i++) {
            int numb = Integer.parseInt(numbers[i]);
            if((numb < 0) || (numb > 255)) {
                return false;
            }
        }
        return true;
    }
}
