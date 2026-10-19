
/*
 * Bubble the largest number (at the end of the array)
 * Time Complexity O(n^2)
 * Space Complexity O(1)
 * */
import java.util.Arrays;

void main() {
    int[] nums = new int[] { 99, 44, 6, 2, 1, 5, 63, 87, 283, 4, 0 };
    bubbleSort(nums);
    System.out.println(Arrays.toString(nums));
}

static void bubbleSort(int[] nums) {
    for (int i = 0; i < nums.length - 1; i++) {
        for (int j = i + 1; j < nums.length; j++) {
            if (nums[i] > nums[j]) {
                int temp = nums[i];
                nums[i] = nums[j];
                nums[j] = temp;
            }
        }
    }
}
