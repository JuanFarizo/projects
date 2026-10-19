void main() {
    int[] nums = new int[] { 1, 2, 3, 4 };

    IO.println(containsDuplicate(nums));
}

public boolean containsDuplicate(int[] nums) {
    Set<Integer> aux = new HashSet<>();
    for (int i = 0; i < nums.length; i++) {
        if (!aux.add(nums[i]))
            return true;
    }
    return false;
}
