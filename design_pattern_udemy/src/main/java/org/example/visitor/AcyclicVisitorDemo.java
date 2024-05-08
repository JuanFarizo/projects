package org.example.visitor;

//Marker interface
interface VisitorAc {
}

interface ExpressionVisitorAc extends VisitorAc {
    void visit(ExpressionAc obj);
}

interface DoubleExpressionVisitorAc extends VisitorAc {
    void visit(DoubleExpressionAc obj);
}

interface AdditionExpressionVisitorAc extends VisitorAc {
    void visit(AdditionExpressionAc obj);
}

abstract class ExpressionAc {
    //Now it's really up to you whether you want a base class implementation or not, because in your
    //case it might not make any sense to have a visitor for an abstract class.
    //But remember, a visitor for an abstract class can serve as a catch-all scenario.
    //So if you didn't implement a visitor for a particular type, but you still want some general sort of
    //catch-all handling of the visitor, you can do it in an abstract class as well.
    public void accept(VisitorAc visitor) {
        if (visitor instanceof ExpressionVisitorAc)
            ((ExpressionVisitorAc) visitor).visit(this);
    }
}

//So even though we have the base interface called Visitor, it doesn't have visit in it.
// So each of these visit implementations is actually kind of voluntary.
// We're actually kind of this visit is not related to this visit,
// which is in turn not related to this visit in any way. They're all independent.
// So now what happens is that every single class and this includes, by the way,
// the expression class has a possibility of implementing an accept method which actually takes a visitor.
class DoubleExpressionAc extends ExpressionAc {
    public double value;

    public DoubleExpressionAc(double value) {
        this.value = value;
    }

    @Override
    public void accept(VisitorAc visitor) {
        if (visitor instanceof DoubleExpressionVisitorAc)
            ((DoubleExpressionVisitorAc) visitor).visit(this);
    }
}

class AdditionExpressionAc extends ExpressionAc {
    public ExpressionAc left, right;

    public AdditionExpressionAc(ExpressionAc left, ExpressionAc right) {
        this.left = left;
        this.right = right;
    }

    @Override
    public void accept(VisitorAc visitor) {
        if (visitor instanceof AdditionExpressionVisitorAc)
            ((AdditionExpressionVisitorAc) visitor).visit(this);
    }
}

class ExpressionPrinterAc
        implements DoubleExpressionVisitorAc, AdditionExpressionVisitorAc {
    private StringBuilder sb;

    public ExpressionPrinterAc(StringBuilder sb) {
        this.sb = sb;
    }

    @Override
    public void visit(DoubleExpressionAc e) {
        sb.append(e.value);
    }

    @Override
    public void visit(AdditionExpressionAc e) {
        sb.append("(");
        e.left.accept(this);
        sb.append("+");
        e.right.accept(this);
        sb.append(")");
    }

}

//different visitors for each of the types of expressions and indeed we can make a visitor for the base abstract class as well.
public class AcyclicVisitorDemo {
    public static void main(String[] args) {
        AdditionExpressionAc e = new AdditionExpressionAc(
                new DoubleExpressionAc(1),
                new AdditionExpressionAc(
                        new DoubleExpressionAc(2),
                        new DoubleExpressionAc(3)
                )
        );
        StringBuilder sb = new StringBuilder();
        ExpressionPrinterAc ep = new ExpressionPrinterAc(sb);
        ep.visit(e);
        System.out.println(sb);
    }
}
