package org.example.decorator;

interface ShapeDynamicOperator {
    String info();
}

class CircleDynamicOperator implements ShapeDynamicOperator {
    private float radius;

    public CircleDynamicOperator() {
    }

    public CircleDynamicOperator(float radius) {
        this.radius = radius;
    }

    void resize(float factor) {
        radius *= factor;
    }

    @Override
    public String toString() {
        return "Circle [radius=" + radius + "]";
    }

    @Override
    public String info() {
        return "Circle [radius=" + radius + "]";
    }

}

class SquareDynamicOperator implements ShapeDynamicOperator {
    private float side;

    public SquareDynamicOperator() {
    }

    public SquareDynamicOperator(float side) {
        this.side = side;
    }

    @Override
    public String toString() {
        return "Square [side=" + side + "]";
    }

    @Override
    public String info() {
        return "Square [side=" + side + "]";
    }

}

// Decorator of shape
class ColoredShapeDynamicOperator implements ShapeDynamicOperator {
    private final ShapeDynamicOperator shapeDynamicOperator;
    private final String color;

    public ColoredShapeDynamicOperator(ShapeDynamicOperator shapeDynamicOperator, String color) {
        this.shapeDynamicOperator = shapeDynamicOperator;
        this.color = color;
    }

    @Override
    public String info() {
        return shapeDynamicOperator.info() + " Has the color" + color;
    }

}

class TransparentShapeDynamicOperator implements ShapeDynamicOperator {
    private final ShapeDynamicOperator shapeDynamicOperator; //Original object in the constructor
    private final int transparency;

    public TransparentShapeDynamicOperator(ShapeDynamicOperator shapeDynamicOperator, int transparency) {
        this.shapeDynamicOperator = shapeDynamicOperator;
        this.transparency = transparency;
    }

    @Override
    public String info() {
        return shapeDynamicOperator.info() + " has transperancy %" + transparency;
    }

}

public class DynamicOperatorDemo {
    public static void main(String[] args) {
        CircleDynamicOperator circleDynamicOperator = new CircleDynamicOperator(10);
        System.out.println(circleDynamicOperator.info());
        ColoredShapeDynamicOperator coloredShape = new ColoredShapeDynamicOperator(new SquareDynamicOperator(20), "blue");
        System.out.println(coloredShape.info());

        TransparentShapeDynamicOperator myCircle = new TransparentShapeDynamicOperator(new ColoredShapeDynamicOperator(new CircleDynamicOperator(5), "green"), 25);
        System.out.println(myCircle.info());
    }
}
