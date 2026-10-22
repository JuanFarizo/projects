void main() {
    System.out.println(isAnagram2("xba", "xab"));
}

static boolean isAnagram(String s, String t) {
    if (s.length() != t.length())
        return false;
    String sSorted = s.chars()
            .sorted()
            .mapToObj(c -> String.valueOf((char) c))
            .collect(Collectors.joining());

    String tSorted = t.chars().sorted()
            .mapToObj(c -> String.valueOf((char) c))
            .collect(Collectors.joining());
    return sSorted.equals(tSorted);
}

static boolean isAnagram2(String s, String t) {
    if (s.length() != s.length())
        return false;

    Map<Character, Integer> coincidences = new HashMap<>();
    for (int i = 0; i < s.length(); i++) {
        coincidences.merge(s.charAt(i), 1, Integer::sum);
    }

    for (int i = 0; i < t.length(); i++) {
        coincidences.merge(t.charAt(i), -1, Integer::sum);
    }
    return coincidences.values().stream().noneMatch(v -> v != 0);
}
