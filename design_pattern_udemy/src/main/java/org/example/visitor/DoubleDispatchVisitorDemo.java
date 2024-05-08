package org.example.visitor;

// Classic visitor
interface ExpressionVisitorDD {

    void visit(DoubleExpressionDD e);

    void visit(AdditionExpressionDD e);
}

class ExpressionCalculatorDD implements ExpressionVisitorDD {
    public double result;

    @Override
    public void visit(DoubleExpressionDD e) {
        result = e.value;
    }

    @Override
    public void visit(AdditionExpressionDD e) {
        e.left.accept(this);
        double a = result;
        e.right.accept(this);
        double b = result;
        result = a + b;
    }

    @Override
    public String toString() {
        return "ExpressionCalculatorDD{" +
                "result=" + result +
                '}';
    }
}

class ExpressionPrinterDD implements ExpressionVisitorDD {
    private StringBuilder sb;

    public ExpressionPrinterDD(StringBuilder sb) {
        this.sb = sb;
    }

    @Override
    public void visit(DoubleExpressionDD e) {
        sb.append(e.value);
    }

    @Override
    public void visit(AdditionExpressionDD e) {
        sb.append("(");
        e.left.accept(this);
        sb.append("+");
        e.right.accept(this);
        sb.append(")");
    }
}

abstract class ExpressionDD {
    public abstract void accept(ExpressionVisitorDD visitor);
}

class DoubleExpressionDD extends ExpressionDD {
    public double value;

    public DoubleExpressionDD(double value) {
        this.value = value;
    }

    @Override
    public void accept(ExpressionVisitorDD visitor) {
        visitor.visit(this);
    }
}

class AdditionExpressionDD extends ExpressionDD {
    public ExpressionDD left, right;

    public AdditionExpressionDD(ExpressionDD left, ExpressionDD right) {
        this.left = left;
        this.right = right;
    }

    @Override
    public void accept(ExpressionVisitorDD visitor) {
        visitor.visit(this);
    }
}

public class DoubleDispatchVisitorDemo {
    public static void main(String[] args) {
        AdditionExpressionDD e = new AdditionExpressionDD(
                new DoubleExpressionDD(1),
                new AdditionExpressionDD(
                        new DoubleExpressionDD(2),
                        new DoubleExpressionDD(3)
                )
        );
        StringBuilder sb = new StringBuilder();
        ExpressionPrinterDD ep = new ExpressionPrinterDD(sb);
        ep.visit(e);
        System.out.println(sb);
        ExpressionCalculatorDD ec = new ExpressionCalculatorDD();
        ec.visit(e);
        System.out.println(ec);
    }
}