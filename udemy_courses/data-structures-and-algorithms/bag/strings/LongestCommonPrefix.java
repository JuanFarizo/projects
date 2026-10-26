void main() {
    // IO.println(longestCommonPrefixHorizontal(new String[] { "flower", "flow",
    // "flight" }));
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
