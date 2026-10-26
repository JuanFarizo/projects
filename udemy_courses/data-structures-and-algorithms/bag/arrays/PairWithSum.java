void main() {
    int[] data = new int[] { 1, 2, 3, 4, 5 }; // Sorted array
    int sum = 8;
    // boolean hasSolution = hasPairWithSum(data, sum);
    System.out.println(Arrays.toString(twoSumSorted(data, sum)));
    // boolean hasSolutionWithHash = hasPairWithSumHash(data, sum);
    // System.out.println(hasSolutionWithHash);
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

// Two Sum on sorted array
static int[] twoSumSorted(int[] a, int target) {
    int l = 0, r = a.length - 1;
    while (l < r) {
        int sum = a[l] + a[r];
        if (sum == target) {
            return new int[] { a[l], a[r] };
        }
        if (sum > target) {
            r--;
        } else {
            l++;
        }
    }
    return new int[] { -1, -1 };
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
