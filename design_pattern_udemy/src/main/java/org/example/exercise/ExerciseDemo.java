package org.example.exercise;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

class Sentence {
    private List<String> words = new ArrayList<>();
    private WordToken[] tokens;

    public Sentence(String plainText) {
        Arrays.stream(plainText.split(" ")).forEach(s -> words.add(s));
        tokens = new WordToken[words.size()];
    }

    public WordToken getWord(int index) {
        if (tokens[index] == null) {
            tokens[index] = new WordToken();
        }
        return tokens[index];
    }

    @Override
    public String toString() {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < tokens.length; i++) {
            if (tokens[i] != null && tokens[i].capitalize) {
                sb.append(words.get(i).toUpperCase());
            } else {
                sb.append(words.get(i));
            }
            if(i != tokens.length -1) sb.append(" ");
        }
        return sb.toString();
    }

    class WordToken {
        public boolean capitalize;
    }   
}

public class ExerciseDemo {
    public static void main(String[] args) {
        var sentence = new Sentence("hello world");
        sentence.getWord(1).capitalize = true;
        System.out.println(sentence);
    }
}
