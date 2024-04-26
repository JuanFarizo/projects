package org.example.interpreter;

import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

class TokenLI {
    public enum TypeLI {
        INTEGER,
        PLUS,
        MINUS,
        LPAREN,
        RPAREN
    }
    public TypeLI typeLI;
    public String text;

    public TokenLI(TypeLI typeLI, String text) {
        this.typeLI = typeLI;
        this.text = text;
    }

    @Override
    public String toString() {
        return "`" + text + "`";
    }
}

public class InterpreterLexing {
    static List<TokenLI> lex(String input) {
        ArrayList<TokenLI> result = new ArrayList<>();
        for(int i = 0; i<input.length(); ++i) {
            switch (input.charAt(i)) {
                case '+':
                    result.add(new TokenLI(TokenLI.TypeLI.PLUS, "+"));
                    break;
                case '-':
                    result.add(new TokenLI(TokenLI.TypeLI.MINUS, "-"));
                    break;
                case '(':
                    result.add(new TokenLI(TokenLI.TypeLI.LPAREN, "("));
                    break;
                case ')':
                    result.add(new TokenLI(TokenLI.TypeLI.RPAREN, ")"));
                    break;
                default:
                    StringBuilder sb = new StringBuilder("" + input.charAt(i));
                    for(int j = i + 1; j < input.length(); ++j) {
                        if(Character.isDigit(input.charAt(j))) {
                            sb.append(input.charAt(j));
                            ++i;
                        } else {
                            result.add(new TokenLI(TokenLI.TypeLI.INTEGER, sb.toString()));
                            break;
                        }
                    }
                    break;
            }
        }
        return result;
    }

    public static void main(String[] args) {
        String input = "(13+4)-(12+1)";
        List<TokenLI> lex = lex(input);
        System.out.println(
                lex.stream()
                        .map(TokenLI::toString)
                        .collect(Collectors.joining("\t"))
        );
    }
}
