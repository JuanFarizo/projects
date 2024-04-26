package org.example.interpreter;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

class ExpressionProcessorEx {
    public Map<Character, Integer> variables = new HashMap<>();

    public int calculate(String expression) {
        return 0;
        // todo
    }

}

class TokenEx {

    public enum TypeEx {
        INTEGER, VARIABLE, PLUS, MINUS;
    }

    public TypeEx typeEx;

    public String text;

    public TokenEx(TypeEx typeEx, String text) {
        this.typeEx = typeEx;
        this.text = text;
    }

    public String toString() {
        return "`" + text + "`";
    }
}

class LexingInterpreterEx {
    static List<TokenEx> lex(String input) {
        List<TokenEx> result = new ArrayList<>();
        for (int i = 0; i < input.length(); i++) {
            switch (input.charAt(i)) {
                case '+':
                    result.add(new TokenEx(TokenEx.TypeEx.PLUS, "+"));
                    break;
                case '-':
                    result.add(new TokenEx(TokenEx.TypeEx.MINUS, "-"));
                    break;
                default:
                    StringBuilder sb = new StringBuilder("" + input.charAt(i));
                    char charAt = 0;
                    for (int j = i + 1; j < input.length(); j++) {
                        charAt = input.charAt(j);
                        if (Character.isDigit(charAt) || Character.isLetter(charAt)) {
                            sb.append(charAt);
                            ++i;
                        } else {
                            break;
                        }
                    }
                    if (Character.isDigit(charAt)) {
                        result.add(new TokenEx(TokenEx.TypeEx.INTEGER, sb.toString()));
                    } else {
                        result.add(new TokenEx(TokenEx.TypeEx.VARIABLE, sb.toString()));
                    }
                    break;
            }
        }

        return result;
    }
}

class InterpreterParsingEx {
    class BinaryOperationEx {
        public Integer left, right;
        public TypeBOEx typeBOEx;

        enum TypeBOEx {
            ADDITION, SUBTRACTION
        }
    }

    static int parse(List<TokenEx> tokens) {
        int result = 0;
        boolean haveLHS = false;
        for (int i = 0; i < tokens.size(); i++) {
            TokenEx token = tokens.get(i);
            switch (token.typeEx) {
                case INTEGER -> {

                }
                case VARIABLE -> {

                }
                case PLUS -> {

                }
                case MINUS -> {

                }
            }
        }
        return result;
    }

}

public class InterpreterExercise {
    public static void main(String[] args) {
        String input = "1+xyz+13";
        List<TokenEx> lex = LexingInterpreterEx.lex(input);
        System.out.println(lex.stream().map(TokenEx::toString).collect(Collectors.joining("\t")));
    }
}
