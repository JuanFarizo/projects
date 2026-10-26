void main() {
    int[] arr1 = { 0, 3, 4, 31 };
    IO.println(Arrays.toString(arr1));
    reverse(arr1);
    IO.println(Arrays.toString(arr1));
    // int[] arr2 = { 4, 6, 30 };
    // int[] sol = mergeSortedArrays(arr2, arr1);
    // IO.println("Primitive array solution");
    // IO.println(Arrays.toString(sol));
    // mergeSortedArrStreamSol(arr1, arr2);
}

private static void mergeSortedArrStreamSol(int[] arr1, int[] arr2) {
    IntStream stream1 = Arrays.stream(arr1);
    IntStream stream2 = Arrays.stream(arr2);
    IntStream sorted = IntStream.concat(stream1, stream2).sorted();
    IO.println("Arr Stream solution");
    IO.println(Arrays.toString(sorted.toArray()));
}

private static int[] mergeSortedArrays(int[] arr1, int[] arr2) {
    int[] solution = new int[arr1.length + arr2.length];
    int indexSol = 0, cursor1 = 0, cursor2 = 0;
    while (cursor1 < arr1.length &&
            cursor2 < arr2.length) {
        if (arr1[cursor1] <= arr2[cursor2]) {
            solution[indexSol] = arr1[cursor1];
            cursor1++;
        } else {
            solution[indexSol] = arr2[cursor2];
            cursor2++;
        }
        indexSol++;
    }

    AddRemainingItems(arr1, arr2, solution, indexSol, cursor1, cursor2);
    return solution;
}

private static void AddRemainingItems(int[] arr1, int[] arr2, int[] solution, int indexSol, int cursor1, int cursor2) {
    if (cursor1 < arr1.length) {
        while (cursor1 < arr1.length) {
            solution[indexSol] = arr1[cursor1];
            cursor1++;
            indexSol++;
        }
    } else {
        while (cursor2 < arr2.length) {
            solution[indexSol] = arr2[cursor2];
            cursor2++;
            indexSol++;
        }
    }
}

// IO.println(Arrays.toString(mergeSorted(new int[] { 1, 3, 5, 7 }, new int[] {
// 2, 4, 6 })));
int[] mergeSorted(int[] a, int[] b) {
    if (a.length == 0 && b.length == 0)
        return new int[0];
    int[] sol = new int[a.length + b.length];
    int leftCursor = 0;
    int rightCursor = 0;
    // Input: a=[1,3,5,7], b=[2,4,6] → Output: [1,2,3,4,5,6,7]
    for (int i = 0; i < sol.length; i++) {
        if (leftCursor == a.length) {
            sol[i] = b[rightCursor++];
            continue;
        } else if (rightCursor == b.length) {
            sol[i] = a[leftCursor++];
            continue;
        }

        if (a[leftCursor] < b[rightCursor]) {
            sol[i] = a[leftCursor++];
        } else {
            sol[i] = b[rightCursor++];
        }
    }
    return sol;
}

static void reverse(int[] a) {
    for (int l = 0, r = a.length - 1; l < r; l++, r--) {
        int t = a[l];
        a[l] = a[r];
        a[r] = t;
    }
}
