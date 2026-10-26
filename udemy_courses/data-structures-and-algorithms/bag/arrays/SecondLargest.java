void main() {
    // IO.println(secondLargest(new int[] { 10, 5, 10 }).orElse(99));
}

OptionalInt secondLargest(int[] a) {
    // 10, 5, 10
    if (a.length == 1)
        return OptionalInt.empty();
    int largest = Integer.MIN_VALUE;
    int secondLargest = Integer.MIN_VALUE;
    for (int i = 0; i < a.length; i++) {
        if (a[i] > largest) {
            secondLargest = largest;
            largest = a[i];
        } else if (a[i] != largest && a[i] > secondLargest) {
            secondLargest = a[i];
        }
    }
    if (largest == secondLargest)
        return OptionalInt.empty();

    return OptionalInt.of(secondLargest);
}
