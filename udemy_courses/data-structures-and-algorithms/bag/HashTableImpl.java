import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public class HashTableImpl {
    void main() {
        HT ht = new HT();
        ht.set("key", "value");
        ht.set("pepe", "trueno");
        System.out.println(ht.get("key"));
        System.out.println(Arrays.toString(ht.keys()));
    }

    static class HT {
        String[][] list = new String[50][2];

        private int hash(String value) {
            if (value == null)
                return 0;
            int hash = 0;
            char[] charArr = value.toCharArray();
            for (char chr : charArr) {
                hash = 31 * hash + chr;
            }
            return Math.abs(hash % 50);
        }

        public void set(String key, String value) {
            list[hash(key)] = new String[] { key, value };
        }

        public String get(String key) {
            return list[hash(key)][1];
        }

        public String[] keys() {
            List<String> keys = new ArrayList<>();
            for (String[] keyValuePair : list) {
                if (keyValuePair[0] != null) {
                    keys.add(keyValuePair[0]);
                }
            }
            return keys.toArray(new String[0]);

        }
    }
}
