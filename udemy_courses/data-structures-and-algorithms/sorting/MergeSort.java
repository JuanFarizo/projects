/*
 * Divide & Conquer Algorithm
 * Split the array in half (until get one element) and compare each element
 * Time Complexity O(n log(n))
 * Space Complexity O(n)
 * */
void main() {
    int[] nums = new int[] { 99, 44, 6, 2, 1, 5, 63, 87, 283, 4, 0 };
    // int[] nums = new int[] { 3, 1, 2 };
    // int[] nums = new int[] { 4, 3, 1, 2};
    int[] sol = mergeSort(nums);
    System.out.println(Arrays.toString(sol));
}

private int[] mergeSort(int[] nums) {
    if(nums.length == 1) {
        return nums;
    }
    int middle = nums.length / 2;
    int[] left = Arrays.copyOfRange(nums, 0, middle);
    int[] right = Arrays.copyOfRange(nums, middle, nums.length);

    return merge(
        mergeSort(left),
        mergeSort(right)
    );
}

private int[] merge(int[] left, int[] right) {
    int[] ordered = new int[left.length + right.length];
    int leftI  = 0;
    int rightI = 0;
    for (int i = 0; i < ordered.length; i++) {
         if (leftI == left.length) {
            ordered[i] = right[rightI++];
            continue;
        } else if (rightI == right.length) {
            ordered[i] = left[leftI++];
            continue;
        }
         if (left[leftI] < right[rightI]) {
            ordered[i] = left[leftI];
            leftI++;
        } else {
            ordered[i] = right[rightI];
            rightI++;
        }
    }
    return ordered;
}
