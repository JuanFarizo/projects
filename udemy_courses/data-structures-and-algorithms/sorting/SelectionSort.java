/*
 * Find the smallest and bring to the first position, then second and so on
 * Time Complexity O(n^2)
 * Space Complexity O(1)
 * */
void main() {
    int[] nums = new int[] { 99, 44, 6, 2, 1, 5, 63, 87, 283, 4, 0 };
    selectionSort(nums);
    System.out.println(Arrays.toString(nums));
}

private void selectionSort(int[] nums) {
    for (int i = 0; i < nums.length - 1; i++) {
        int smallestIndex = i;
        int smallestValue = nums[i];
        for (int j = i + 1; j < nums.length; j++) {
            if (smallestValue > nums[j]) {
                smallestValue = nums[j];
                smallestIndex = j;
            }
        }
        if (smallestIndex != i) {
            int temp = nums[i];
            nums[i] = nums[smallestIndex];
            nums[smallestIndex] = temp;
        }
    }
}
