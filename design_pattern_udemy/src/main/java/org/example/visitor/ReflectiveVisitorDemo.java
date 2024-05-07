package org.example.visitor;

//use reflection
class ExpressionPrinterRV {
    public void print(ExpressionRV e, StringBuilder sb) {
        if (e.getClass() == DoubleExpressionRV.class) {
            sb.append(((DoubleExpressionRV) e).value);
        } else if (e.getClass() == AdditionExpressionRV.class) {
            sb.append("(");
            print(((AdditionExpressionRV) e).left, sb);
            sb.append("+");
            print(((AdditionExpressionRV) e).right, sb);
            sb.append(")");
        }
    }
}

abstract class ExpressionRV {
    //1+2
}

class DoubleExpressionRV extends ExpressionRV {
    public double value;

    public DoubleExpressionRV(double value) {
        this.value = value;
    }

}

class AdditionExpressionRV extends ExpressionRV {
    public ExpressionRV left, right;

    public AdditionExpressionRV(ExpressionRV left, ExpressionRV right) {
        this.left = left;
        this.right = right;
    }
}

public class ReflectiveVisitorDemo {
    public static void main(String[] args) {
        AdditionExpressionRV e = new AdditionExpressionRV(
                new DoubleExpressionRV(1),
                new AdditionExpressionRV(
                        new DoubleExpressionRV(2),
                        new DoubleExpressionRV(3)
                )
        );
        StringBuilder sb = new StringBuilder();
        ExpressionPrinterRV ep = new ExpressionPrinterRV();
        ep.print(e, sb);
        System.out.println(sb);
    }
}
