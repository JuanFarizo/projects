import static java.util.Objects.compare;
import static java.util.stream.Collectors.counting;
import static java.util.stream.Collectors.groupingBy;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.stream.Collector;
import java.util.stream.Collector;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

void main() {
    String test = "The quick brown fox jumps over the lazy dog. The end!";
    Map<String, Long> stringLongMap = wordFrequency(test);
    System.out.println(stringLongMap);
}

// Enunciado. Dada una lista de strings, devolvé solo los que son palíndromos,
// usando Java Streams. Ignorá mayúsculas/minúsculas. Los strings vacíos y los
// null no cuentan.
// Firma: List<String> palindromes(List<String> words)
// Input: ["madam", "java", "level", "stream", "noon", "Anna", ""]
// Output esperado: [madam, level, noon, Anna]
// Constraints: respetar el orden original; no mutar la lista de entrada;
// O(total de caracteres).
Predicate<String> isPalindrome = s -> {
    char[] charArray = s.toCharArray();
    for (int i = 0; i < charArray.length / 2; i++) {
        if (charArray[i] != charArray[charArray.length - i - 1]) {
            return false;
        }
    }
    return true;
};

List<String> palindromes(List<String> words) {
    return words.stream()
            .filter(s -> !s.isBlank())
            .filter(isPalindrome)
            .collect(Collectors.toList());
}

// Enunciado. Dado un array de enteros no negativos, devolvé un Map cuyas claves
// son los rangos "0-9", "10-19", ... y cuyos valores son los números que caen
// en cada rango, usando Java 8+ streams. Los rangos deben salir ordenados
// numéricamente.
// Firma: Map<String, List<Integer>> groupByRange(int[] nums)
// Input: [1, 5, 12, 18, 25, 9, 30, 11, 105]
// Output esperado: {0-9=[1, 5, 9], 10-19=[12, 18, 11], 20-29=[25], 30-39=[30],
// 100-109=[105]}
// Constraints: los números dentro de cada rango mantienen el orden de
// aparición; no incluir rangos vacíos. Trampa: ordenar por la clave String
// pondría "100-109" antes de "20-29".

Map<String, List<Integer>> groupByRange(int[] nums) {
    return IntStream.of(nums)
            .boxed()
            .collect(groupingBy(num -> {
                int res = num / 10;
                return (res * 10) + "," + (res * 10 + 9);
            }));
}

// Enunciado. Contá cuántas veces aparece cada palabra en un texto. Ignorá
// mayúsculas y signos de puntuación.
// Firma: Map<String, Long> wordFrequency(String text)
// Input: "The quick brown fox jumps over the lazy dog. The end!"
// Output esperado (orden de primera aparición): {the=3, quick=1, brown=1,
// fox=1, jumps=1, over=1, lazy=1, dog=1, end=1}
// Constraints: una sola pasada; texto de hasta 10⁶ caracteres.

static Map<String, Long> wordFrequency(String text) {
    return Arrays.stream(text.toLowerCase().split("\\W+"))
            .filter(w -> !w.isEmpty())
            .collect(groupingBy(Function.identity(), LinkedHashMap::new, counting()));
}

static void ejer1() {
    int[] nums = new int[] { 1, 2, 3 };
    List<Integer> list = IntStream.of(nums)
            .boxed()
            .collect(Collectors.toList());
}

static void ejer2() {
    List<String> words = new ArrayList<>();
    words.add("mama");
    words.add("madam");
    words.add("pepe");
    words.stream()
            .filter(w -> {
                return Objects.nonNull(w) && !w.isBlank();
            }).toList();

    List<String> sol = words.stream()
            .filter(Objects::nonNull)
            .filter(w -> !w.isBlank())
            .filter(w -> isPalindrome(w))
            .toList();
    System.out.println(sol);
}

static boolean isPalindrome(String s) {
    String t = s.toLowerCase(Locale.ROOT);
    return IntStream.range(0, t.length() / 2)
            .allMatch(i -> t.charAt(i) == t.charAt(t.length() - 1 - i));

}

static void ejer3(int[] nums) {
    IntStream.of(nums)
            .boxed()
            .sorted(Comparator.comparingInt(n -> n / 10))
            .collect(Collectors.groupingBy(n -> (n / 10 * 10) + "-" + (n / 10 * 10 + 9),
                    LinkedHashMap::new,
                    Collectors.toList()));
}

static void ejer4(String[] words) {
    List<String> sortedWords = Arrays.stream(words)
            .sorted(Comparator.comparingInt(String::length)
                    .reversed()
                    .thenComparing(Comparator.naturalOrder()))
            .toList();

    List<String> sortedWords1 = Arrays.stream(words)
            .sorted(Comparator.comparingInt(String::length))
            .toList();

    System.out.println(sortedWords);
    System.out.println(sortedWords1);
}

static void ejer5(String text) {
    Collector<Object,StringBuilder,String> customCollector = Collector.of(StringBuilder::new,
                    (sb, s) -> sb.append(s),
                    (a, b) -> a.append(b),
                    StringBuilder::toString);
    String[] split = text.toLowerCase(Locale.ROOT).split("\\W+");
    Map<String, Long> solution = Arrays.stream(split)
            .filter(w -> !w.isBlank())
            .collect(Collectors.groupingBy(
                                Function.identity(),
                                LinkedHashMap::new,
                                Collectors.counting())
            );
    System.out.println(solution);
}

public static void main(String[] args) {
    ejer5("The quick brown fox jumps over the lazy dog. The end!");
}
