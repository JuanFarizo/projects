void main() {
    String toReverse = "falopa";
    List<Character> collect = toReverse.chars().mapToObj(c -> (char) c).collect(Collectors.toList());
    IO.println(collect.reversed());
    reversedForce();
}

static void reversedForce() {
    String toReverse = "falopa";
    char[] charArr = toReverse.toCharArray();
    char[] reversed = new char[charArr.length];
    int reversedIndex = 0;
    for (int i = charArr.length - 1; i >= 0; i--) {
        reversed[reversedIndex] = charArr[i];
        reversedIndex++;
    }
    IO.println(new String(reversed));
}
