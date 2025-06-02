package org.example.visitor;

import static org.junit.jupiter.api.Assertions.assertEquals;

abstract class ExpressionVisitorEx {
    abstract void visit(ValueEx value);

    abstract void visit(AdditionExpressionEx ae);

    abstract void visit(MultiplicationExpressionEx me);
}

abstract class ExpressionEx {
    abstract void accept(ExpressionVisitorEx ev);
}

class ValueEx extends ExpressionEx {
    public int value;

    public ValueEx(int value) {
        this.value = value;
    }

    @Override
    void accept(ExpressionVisitorEx ev) {
        ev.visit(this);
    }
}

class AdditionExpressionEx extends ExpressionEx {
    public ExpressionEx lhs, rhs;

    public AdditionExpressionEx(ExpressionEx lhs, ExpressionEx rhs) {
        this.lhs = lhs;
        this.rhs = rhs;
    }

    @Override
    void accept(ExpressionVisitorEx ev) {
        ev.visit(this);
    }
}

class MultiplicationExpressionEx extends ExpressionEx {
    public ExpressionEx lhs, rhs;

    public MultiplicationExpressionEx(ExpressionEx lhs, ExpressionEx rhs) {
        this.lhs = lhs;
        this.rhs = rhs;
    }

    @Override
    void accept(ExpressionVisitorEx ev) {
        ev.visit(this);
    }
}

class ExpressionPrinterEx extends ExpressionVisitorEx {
    private StringBuilder sb = new StringBuilder();

    // todo: overrides
    @Override
    public void visit(AdditionExpressionEx e) {
        sb.append("(");
        e.lhs.accept(this);
        sb.append("+");
        e.rhs.accept(this);
        sb.append(")");
    }

    @Override
    public void visit(ValueEx v) {
        sb.append(v.value);
    }

    @Override
    public void visit(MultiplicationExpressionEx e) {
        e.lhs.accept(this);
        sb.append("*");
        e.rhs.accept(this);
    }

    @Override
    public String toString() {
        return sb.toString();
    }
}

public class VisitorDDExercise {
    public static void main(String[] args) {
        AdditionExpressionEx simple = new AdditionExpressionEx(new ValueEx(2), new ValueEx(3));
        ExpressionPrinterEx ep = new ExpressionPrinterEx();
        ep.visit(simple);
        assertEquals("(2+3)", ep.toString());
    }
}
