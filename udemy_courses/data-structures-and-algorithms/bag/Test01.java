import java.util.HashSet;
import java.util.Set;

public class Test01 {
    public static void main(String[] args) {
        int[] data = new int[] { 1, 2, 3, 4}; // Sorted array
        int sum = 8;
        // boolean hasSolution = hasPairWithSum(data, sum);
        boolean hasSolutionWithHash = hasPairWithSumHash(data, sum);
        System.out.println(hasSolutionWithHash);
        // System.out.println(hasSolution);
    }

    private static boolean hasPairWithSumHash(int[] data, int sum) {
        Set<Integer> comp = new HashSet<>();
        for (Integer num : data) {
            if (comp.contains(num)) {
                System.out.println("The solution is num: " + num + " and " + (sum - num));
                return true;
            }
            comp.add(sum - num);
        }
        return false;
    }

    private static boolean hasPairWithSum(int[] data, int sum) {
        System.out.println(data.length);
        assert data.length > 2 : "Not enough data";
        int start = 0;
        int end = data.length - 1;
        int acc;
        while (start < end) {
            acc = data[start] + data[end];
            System.out.println("Accu: " + acc);
            if (acc == sum) {
                return true;
            }
            if (acc > sum)
                end--;
            else
                start++;
        }
        return false;
    }
}
