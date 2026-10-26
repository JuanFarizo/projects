void main() {
    // String[] arr1 = new String[] { "a", "b", "c", "d" };
    // String[] arr2 = new String[] { "x", "y", "z", "r" };
    // boolean isMatch = hasMatch(arr1, arr2);
    // boolean isMatchHash = hasMatchHash(arr1, arr2);
    // boolean isMatchHash2 = hasMatchHash2(arr1, arr2);
}

private static boolean hasMatchHash2(String[] arr1, String[] arr2) {
    Set<String> set = Set.of(arr2);
    return Stream.of(arr1).anyMatch(set::contains);
}

private static boolean hasMatchHash(String[] arr1, String[] arr2) {
    assert arr1.length > 1 && arr2.length > 1 : "At least one array is empty";
    Set<String> set = Set.of(arr2);
    for (int i = 0; i < arr1.length; i++) {
        if (set.contains(arr1[i]))
            return true;
    }
    return false;
}

private static boolean hasMatch(String[] arr1, String[] arr2) {
    for (int i = 0; i < arr1.length; i++) {
        for (int j = 0; j < arr2.length; j++) {
            if (arr1[i] == arr2[j])
                return true;
        }
    }
    return false;
}
