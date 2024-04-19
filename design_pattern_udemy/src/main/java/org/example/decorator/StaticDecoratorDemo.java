package org.example.decorator;

import java.util.function.Supplier;

interface ShapeSD {
    String info();
}

class CircleSD implements ShapeSD {
    private float radius;

    public CircleSD() {
    }

    public CircleSD(float radius) {
        this.radius = radius;
    }

    void resize(float factor) {
        radius *= factor;
    }

    @Override
    public String info() {
        return "Circle [radius=" + radius + "]";
    }

}

class SquareSD implements ShapeSD {
    private float side;

    public SquareSD() {
    }

    public SquareSD(float side) {
        this.side = side;
    }

    @Override
    public String info() {
        return "Square [side=" + side + "]";
    }
}

class ColoredShapeSD<T extends ShapeSD> implements ShapeSD {
    private ShapeSD shapeDynamicOperator;
    private String color;

    public ColoredShapeSD(Supplier<? extends T> ctor, String color) {
        this.shapeDynamicOperator = ctor.get();
        this.color = color;
    }

    @Override
    public String info() {
        return shapeDynamicOperator.info() + " has the color  " + color;
    }
}

class TransparentShapeSD<T extends ShapeSD> implements ShapeSD {
    private ShapeSD shapeDynamicOperator;
    private int transperancy;

    public TransparentShapeSD(Supplier<? extends T> ctor, int transperancy) {
        this.shapeDynamicOperator = ctor.get();
        this.transperancy = transperancy;
    }

    @Override
    public String info() {
        return shapeDynamicOperator.info() + " has the transparency " + transperancy;
    }

}

public class StaticDecoratorDemo {
    public static void main(String[] args) {
        ColoredShapeSD<SquareSD> blueSquare = new ColoredShapeSD<>(
            () -> new SquareSD(20),
            "blue"
        );
        System.out.println(blueSquare.info());
        TransparentShapeSD<ColoredShapeSD<CircleSD>> myCircle = new TransparentShapeSD<>(
                () -> new ColoredShapeSD<>(() -> new CircleSD(5), "blue"), 50);

        System.out.println(myCircle.info());
    }
}
