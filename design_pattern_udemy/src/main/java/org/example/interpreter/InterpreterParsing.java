package org.example.interpreter;

import java.util.List;
import java.util.stream.Collectors;

interface ElementPI {
    int eval();
}

class IntegerPI implements ElementPI {
    private int val;

    public IntegerPI(int val) {
        this.val = val;
    }

    @Override
    public int eval() {
        return val;
    }
}

class BinaryOperationPI implements ElementPI {
    @Override
    public int eval() {
        switch (type) {
            case ADDITION -> {
                return left.eval() + right.eval();
            }
            case SUBTRACTION -> {
                return left.eval() - right.eval();
            }
            default -> {
                return 0;
            }
        }
    }

    public enum TypePI {
        ADDITION, SUBTRACTION
    }

    public TypePI type;
    public ElementPI left, right;
}

public class InterpreterParsing {
    static ElementPI parse(List<TokenLI> tokens) {
        BinaryOperationPI result = new BinaryOperationPI();
        boolean haveLHS = false;
        for (int i = 0; i < tokens.size(); i++) {
            TokenLI token = tokens.get(i);
            switch (token.typeLI) {
                case INTEGER -> {
                    IntegerPI integerPI = new IntegerPI(Integer.parseInt(token.text));
                    if (!haveLHS) {
                        result.left = integerPI;
                    } else {
                        result.right = integerPI;
                    }
                }
                case PLUS -> {
                    result.type = BinaryOperationPI.TypePI.ADDITION;
                }
                case MINUS -> {
                    result.type = BinaryOperationPI.TypePI.SUBTRACTION;
                }
                case LPAREN -> {
                    int j = 0; // location of rparen
                    for (; j < tokens.size(); ++j)
                        if (tokens.get(j).typeLI == TokenLI.TypeLI.RPAREN)
                            break;
                    List<TokenLI> subexpression = tokens.stream().skip(i + 1).limit(j - i - 1).collect(Collectors.toList());
                    ElementPI element = parse(subexpression);
                    if (!haveLHS) {
                        result.left = element;
                        haveLHS = true;
                    } else
                        result.right = element;
                    i = j;
                }
            }
        }
        return result;
    }

    public static void main(String[] args) {
        String input = "13+4-12+1";
        List<TokenLI> lex = InterpreterLexing.lex(input);
        System.out.println(
                lex.stream()
                        .map(TokenLI::toString)
                        .collect(Collectors.joining("\t"))
        );
        ElementPI parsed = parse(lex);
        System.out.println(input + " = " + parsed.eval());
    }
}
