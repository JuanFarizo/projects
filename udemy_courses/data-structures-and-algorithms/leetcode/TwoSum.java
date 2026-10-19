void main() {
    int[] nums = { 2, 7, 11, 15 };
    // int[] test = { 3, 3 };
    // int[] test2 = { 3, 2, 4 };
    int target = 26;
    int[] sol = twoSum2(nums, target);
    IO.println(Arrays.toString(sol));
}

static int[] twoSum(int[] nums, int target) {
    int[] sol = new int[2];
    for (int i = 0; i < nums.length - 1; i++) {
        for (int j = 1; j < nums.length; j++) {
            if (target == nums[i] + nums[j]) {
                sol[0] = i;
                sol[1] = j;
            }
        }
    }
    return sol;
}

static int[] twoSum2(int[] nums, int target) {
    int[] sol = new int[2];
    Map<Integer, Integer> complementPosition = new HashMap<>();
    for (int i = 0; i < nums.length; i++) {
        if (complementPosition.containsKey(nums[i]) &&
            complementPosition.get(nums[i]) != i) {
            sol[0] = complementPosition.get(nums[i]);
            sol[1] = i;
            return sol;
        }
        complementPosition.put(target - nums[i], i);

    }
    return sol;
}
