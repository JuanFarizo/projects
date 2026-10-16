import java.util.Arrays;

public class MoveZeroes {
    void main() {
        int[] nums = new int[] { 1, 0, 0, 3, 12 };
        moveZeroes4(nums);
    }

    static void moveZeroes(int[] nums) {
        boolean hasZero = false;
        int leftMostPos = nums.length - 1;
        int offset = 0;
        for (int i = 0; i < nums.length; i++) {
            if (nums[i] == 0) {
                hasZero = true;
                if (leftMostPos > i)
                    leftMostPos = i;
                else
                    offset++;
            }
            if (hasZero && nums[i] != 0) {
                nums[leftMostPos] = nums[i];
                nums[i] = 0;
                if (offset > 0) {
                    leftMostPos++;
                } else {
                    leftMostPos = i;
                }
            }
        }
    }

    static void moveZeroes4(int[] nums) {
        int left = 0;
        for (int right = 0; right < nums.length; right++) {
            if (nums[right] != 0) {
                int temp = nums[right];
                nums[right] = nums[left];
                nums[left] = temp;
                left++;
            }
        }
        System.out.println(Arrays.toString(nums));
    }

    static void moveZeroes3(int[] nums) {
        int cursor = 0;
        for (int i = 0; cursor + i < nums.length - 1;) {
            if (nums[cursor + i] == 0 && nums[cursor + i + 1] != 0) {
                nums[cursor + i] = nums[cursor + i + 1];
                nums[cursor + i + 1] = 0;
                i = 0;
            } else {
                i++;
            }
        }
        System.out.println(Arrays.toString(nums));
    }

    static void moveZeroes2(int[] nums) {
        int[] sol = new int[nums.length];
        int freePos = 0;
        for (int value : nums) {
            if (value != 0) {
                sol[freePos] = value;
                freePos++;
            }
        }
        System.out.println(Arrays.toString(sol));
    }
}
