package org.example.flyweight;

import java.util.ArrayList;
import java.util.List;

class FormattedText {
    private String plainText;
    private boolean[] capitalize;

    public FormattedText(String plainText) {
        this.plainText = plainText;
        capitalize = new boolean[plainText.length()];
    }

    public void capitalize(int start, int end) {
        for (int i = start; i < end; i++) {
            capitalize[i] = true;
        }
    }

    @Override
    public String toString() {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < plainText.length(); i++) {
            char c = plainText.charAt(i);
            sb.append(capitalize[i] ? Character.toUpperCase(c) : c);
        }
        return sb.toString();
    }

}

class FlyweightFormattedText {
    private String plainText;
    private List<TextRange> formatting = new ArrayList<>();

    public FlyweightFormattedText(String plainText) {
        this.plainText = plainText;
    }

    public TextRange getRange(int start, int end) {
        TextRange textRange = new TextRange(start, end);
        formatting.add(textRange);
        return textRange;
    }

    @Override
    public String toString() {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < plainText.length(); i++) {
            char c = plainText.charAt(i);
            for (TextRange tr : formatting) {
                if (tr.covers(i) && tr.capitalize) {
                    c = Character.toUpperCase(c);
                }
                sb.append(c);
            }
        }
        return sb.toString();
    }

    public class TextRange {
        public int start, end;
        public boolean capitalize, bold, italic;

        public TextRange(int start, int end) {
            this.start = start;
            this.end = end;
        }

        public boolean covers(int position) {
            return position >= start && position <= end;
        }

    }
}

public class FlyweightFormattedTextDemo {
    public static void main(String[] args) {
        FormattedText text = new FormattedText("pepetrueno");
        text.capitalize(3, 6);

        FlyweightFormattedText fft = new FlyweightFormattedText("make argentina great again");
        fft.getRange(5, 13).capitalize = true;

        System.err.println(text);
        System.out.println(fft);
    }
}
