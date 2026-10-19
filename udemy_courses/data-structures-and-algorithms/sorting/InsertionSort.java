/*
 * Usefull when  the list is almost sorted
 * Or small datasets
 * */
void main() {
    int[] nums = new int[] { 99, 44, 6, 2, 1, 5, 63, 87, 283, 4, 0 };
    // int[] nums = new int[] { 3, 1, 2 };
    // int[] nums = new int[] { 4, 3, 1, 2};
    insertionSort(nums);
    System.out.println(Arrays.toString(nums));
}

private void insertionSort(int[] nums) {
    for (int i = 1; i < nums.length; i++) {
        int posValue = nums[i];
        int shiftPos = 0;
        for (int j = i - 1; j >= 0; j--) {
            if(posValue > nums[j]) {
                break;
            }
            shiftPos++;
        }
        if(shiftPos != 0) {
            for (int k = 0; k < shiftPos; k++) {
                nums[i-k] = nums[i-k-1];
            }
            nums[i - shiftPos] = posValue;
        }
    }
}
