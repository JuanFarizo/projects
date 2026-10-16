public class MaximumSubarray {
    void main() {
        int[] nums = { -2, 1, -3, 4, -1, 2, 1, -5, 4 };
        int[] nums2 = { 5, 4, -1, 7, 8 };
        int sol = maxSubArray(new int[] { -2, 1, -3, 4, -1, 2, 1, -5, 4 });
        System.out.println("Solution: " + sol);
    }

    static int maxSubArray(int[] nums) {
        // sol = 6 | subarray: [4,-1,2,1]
        int sol = nums[0];
        int acc = nums[0];
        for (int i = 1; i < nums.length; i++) {
            int value = nums[i];
            if (acc < 0 && value > acc) {
                acc = value;
            } else {
                acc = acc + value;
            }

            if (acc > sol) {
                sol = acc;
            }
        }

        return sol;
    }

}
