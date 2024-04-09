package org.example.decorator;

import java.util.function.Supplier;

interface Shape {
    String info();
}

class Circle implements Shape {
    private float radius;

    public Circle() {
    }

    public Circle(float radius) {
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

class Square implements Shape {
    private float side;

    public Square() {
    }

    public Square(float side) {
        this.side = side;
    }

    @Override
    public String info() {
        return "Square [side=" + side + "]";
    }
}

class ColoredShape<T extends Shape> implements Shape {
    private Shape shape;
    private String color;

    public ColoredShape(Supplier<? extends T> ctor, String color) {
        this.shape = ctor.get();
        this.color = color;
    }

    @Override
    public String info() {
        return shape.info() + " has the color  " + color;
    }
}

class TransparentShape<T extends Shape> implements Shape {
    private Shape shape;
    private int transperancy;

    public TransparentShape(Supplier<? extends T> ctor, int transperancy) {
        this.shape = ctor.get();
        this.transperancy = transperancy;
    }

    @Override
    public String info() {
        return shape.info() + " has the transparency " + transperancy;
    }

}

public class StaticDecoratorDemo {
    public static void main(String[] args) {
        ColoredShape<Square> blueSquare = new ColoredShape<>(
            () -> new Square(20), 
            "blue"
        );
        System.out.println(blueSquare.info());
        TransparentShape<ColoredShape<Circle>> myCircle = new TransparentShape<>(
                () -> new ColoredShape<>(() -> new Circle(5), "blue"), 50);

        System.out.println(myCircle.info());
    }
}
