package org.example.visitor;


abstract class ExpressionV {
    //1+2
    public abstract void print(StringBuilder sb); // This breaks open close principle and single responsaiblity principle
}

class DoubleExpression extends ExpressionV {
    private double value;

    public DoubleExpression(double value) {
        this.value = value;
    }

    @Override
    public void print(StringBuilder sb) {
        sb.append(value);
    }
}

class AdditionExpression extends ExpressionV {
    private ExpressionV left, right;

    public AdditionExpression(ExpressionV left, ExpressionV right) {
        this.left = left;
        this.right = right;
    }

    @Override
    public void print(StringBuilder sb) {
        sb.append("(");
        left.print(sb);
        sb.append("+");
        right.print(sb);
        sb.append(")");
    }
}
public class IntrusiveVisitorDemo {
    public static void main(String[] args) {
        AdditionExpression e = new AdditionExpression(
                new DoubleExpression(1),
                new AdditionExpression(
                        new DoubleExpression(2),
                        new DoubleExpression(3)
                )
        );
        StringBuilder sb = new StringBuilder();
        e.print(sb);
        System.out.println(sb);
    }
}
