import java.util.Arrays;

public class RotateArray {
    void main() {
        int[] nums = new int[] { 1,2,3,4,5,6,7 };
        int k = 3;
        rotate3(nums, k);
    }

    public void rotate2(int[] nums, int k) {
        if (k > nums.length) {
            k = k % nums.length;
        }
        if (k == 0)
            return;
        int[] valuesToShift = new int[k];
        int rightPointer = nums.length - k;
        for (int i = 0; i < valuesToShift.length; i++) {
            valuesToShift[i] = nums[rightPointer + i];
        }
        int[] sol = new int[nums.length];
        for (int i = 0; i < sol.length; i++) {
            if (i < k) {
                sol[i] = valuesToShift[i];
            } else {
                sol[i] = nums[i - k];
            }
        }
    }

    void rotate3(int[] nums, int k) {
        if (k > nums.length) {
            k = k % nums.length;
        }
        if (k == 0)
            return;
        int[] valuesToShift = new int[k];
        int rightPointer = nums.length - k; // 4
        for (int i = 0; i < nums.length; i++) {
            if(k > i) {
                valuesToShift[i] = nums[rightPointer+i];
            } else {
                int leftPointer = nums.length - 1 - i;
                nums[leftPointer+k] = nums[leftPointer];
            }
        }

        for (int i = 0; i < valuesToShift.length; i++) {
            nums[i] = valuesToShift[i];
        }
    }

    public void rotate(int[] nums, int k) {
        if (k > nums.length) {
            k = k % nums.length;
        }
        if (k == 0)
            return;

        int actualPos = 0;
        int valueToRotate = nums[actualPos];
        int nextPos;
        for (int i = 0; i < nums.length; i++) {
            if (actualPos + k > nums.length - 1) {
                nextPos = (actualPos + k) % (nums.length);
            } else {
                nextPos = actualPos + k;
            }
            int temp = nums[nextPos];
            nums[nextPos] = valueToRotate;
            valueToRotate = temp;
            actualPos = nextPos;

        }
        System.out.println(Arrays.toString(nums));

    }
}
