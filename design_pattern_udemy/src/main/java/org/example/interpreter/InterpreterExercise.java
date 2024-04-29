package org.example.interpreter;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import org.apache.commons.lang3.StringUtils;

class ExpressionProcessorEx {
    public Map<Character, Integer> variables = new HashMap<>();

    public int calculate(String expression) {
        List<TokenEx> lex = LexingInterpreterEx.lex(expression);
        InterpreterParsingEx interpreterParsingEx = new InterpreterParsingEx(lex, variables);
        return interpreterParsingEx.evaluate();
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
                    if (StringUtils.isNumeric(sb.toString())) {
                        result.add(new TokenEx(TokenEx.TypeEx.INTEGER, sb.toString()));
                    } else if (StringUtils.isAlpha(sb.toString())) {
                        result.add(new TokenEx(TokenEx.TypeEx.VARIABLE, sb.toString()));
                    }
                    break;
            }
        }

        return result;
    }
}

class InterpreterParsingEx {
    private final Map<Character, Integer> variables;
    private final List<TokenEx> tokens;

    public InterpreterParsingEx(List<TokenEx> tokens, Map<Character, Integer> variables) {
        this.variables = variables;
        this.tokens = tokens;
    }

    public int evaluate() {
        return this.parseTokens();
    }

    static class BinaryOperationEx {
        public Integer left, right;
        public TypeBOEx typeBOEx;

        enum TypeBOEx {
            ADDITION, SUBTRACTION
        }

        public int eval() {
            switch (typeBOEx) {
                case ADDITION -> {
                    return left + right;
                }
                case SUBTRACTION -> {
                    return left - right;
                }
                default -> {
                    return 0;
                }
            }
        }
    }

    // Has to return 0 1+xyz+13
    // var x = 3. Has to return 1+3+13 = 17 1+x+13
    private int parseTokens() {
        int result = 0;
        boolean haveLHS = false;
        BinaryOperationEx bo = new BinaryOperationEx();
        for (TokenEx token : tokens) {
            switch (token.typeEx) {
                case INTEGER -> {
                    if (!haveLHS) {
                        bo.left = Integer.valueOf(token.text);
                        haveLHS = true;
                    } else {
                        bo.right = Integer.valueOf(token.text);
                        result = bo.eval();
                        bo.left = result;
                    }
                }
                case VARIABLE -> {
                    if (token.text.length() > 1 || !variables.containsKey(token.text.charAt(0))) {
                        return 0;
                    } else {
                        if (!haveLHS) {
                            bo.left = variables.get(token.text.charAt(0));
                            haveLHS = true;
                        } else {
                            bo.right = variables.get(token.text.charAt(0));
                            result = bo.eval();
                            bo.left = result;
                        }
                    }
                }
                case PLUS -> {
                    bo.typeBOEx = BinaryOperationEx.TypeBOEx.ADDITION;
                }
                case MINUS -> {
                    bo.typeBOEx = BinaryOperationEx.TypeBOEx.SUBTRACTION;
                }
            }
        }
        return result;
    }

}

public class InterpreterExercise {
    public static void main(String[] args) {
        String input = "1+3+13-v+x";
        List<TokenEx> lex = LexingInterpreterEx.lex(input);
        System.out.println(lex.stream().map(TokenEx::toString).collect(Collectors.joining("\t")));
        ExpressionProcessorEx expressionProcessorEx = new ExpressionProcessorEx();
        expressionProcessorEx.variables.put('v', 3);
        expressionProcessorEx.variables.put('x', 5);
        System.out.println(expressionProcessorEx.calculate(input));
    }
}
