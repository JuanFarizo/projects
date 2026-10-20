void main() {
    // String[] arr1 = new String[] { "a", "b", "c", "d" };
    // String[] arr2 = new String[] { "x", "y", "z", "r" };
    // boolean isMatch = hasMatch(arr1, arr2);
    // boolean isMatchHash = hasMatchHash(arr1, arr2);
    // boolean isMatchHash2 = hasMatchHash2(arr1, arr2);
    // IO.println(Arrays.toString(mergeSorted(new int[] { 1, 3, 5, 7 }, new int[] {
    // 2, 4, 6 })));
    // IO.println(addStrings("999", "11"));
    System.out.println("5".charAt(0));
    // IO.println(secondLargest(new int[] { 10, 5, 10 }).orElse(99));
    // IO.println(longestCommonPrefixHorizontal(new String[] { "flower", "flow",
    // "flight" }));
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

static String longestCommonPrefix(String[] strs) {
    // "flower", "flow", "flight"
    if (strs.length == 1)
        return strs[0];
    StringBuilder sol = new StringBuilder();
    boolean hasMatch = true;
    int cursor = 0;
    while (hasMatch) {
        for (int i = 0; i < strs.length - 1; i++) {
            if ((cursor >= strs[i].length() ||
                    cursor >= strs[i + 1].length()) ||
                    strs[i].charAt(cursor) != strs[i + 1].charAt(cursor)) {
                hasMatch = false;
                break;
            }
        }
        if (hasMatch) {
            sol.append(strs[0].charAt(cursor));
            cursor++;
        }
    }
    return sol.toString();
}

static String longestCommonPrefixHorizontal(String[] strs) {
    if (strs.length == 1)
        return strs[0];
    // "flower", "flow", "flight"
    String prefix = strs[0];

    for (int i = 0; i < strs.length; i++) {
        while (!strs[i].startsWith(prefix)) {
            System.out.println(prefix);
            prefix = prefix.substring(0, prefix.length() - 1);
            if (prefix.isBlank())
                return "";
        }
    }

    return prefix;
}

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

public String addStrings(String a, String b) {
    StringBuilder sol = new StringBuilder();
    // Punteros para recorrer los strings de derecha a izquierda
    int leftC = a.length() - 1;
    int rightC = b.length() - 1;
    int carry = 0; // Acarreo de la suma

    // Iteramos mientras haya dígitos por procesar o un acarreo pendiente
    while (leftC >= 0 || rightC >= 0 || carry > 0) {
        int sum = carry;
        // Sumamos el dígito de 'a' si aún quedan caracteres
        if (leftC >= 0) {
            sum += a.charAt(leftC) - '0'; // Conversión de char a int de forma eficiente
            leftC--;
        }

        // Sumamos el dígito de 'b' si aún quedan caracteres
        if (rightC >= 0) {
            sum += b.charAt(rightC) - '0';
            rightC--;
        }

        // El nuevo dígito a agregar es el resto de la división por 10
        sol.append(sum % 10);

        // Calculamos el nuevo acarreo para la siguiente columna
        carry = sum / 10;
    }

    // Como sumamos de derecha a izquierda, el resultado está invertido
    return sol.reverse().toString();
}
