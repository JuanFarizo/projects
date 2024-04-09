package org.example.decorator;

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
    public String toString() {
        return "Circle [radius=" + radius + "]";
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
    public String toString() {
        return "Square [side=" + side + "]";
    }

    @Override
    public String info() {
        return "Square [side=" + side + "]";
    }

}

// Decorator of shape
class ColoredShape implements Shape {
    private Shape shape;
    private String color;

    public ColoredShape(Shape shape, String color) {
        this.shape = shape;
        this.color = color;
    }

    @Override
    public String info() {
        return shape.info() + " Has the color" + color;
    }

}

class TransparentShape implements Shape {
    private Shape shape; //Original object in the constructor
    private int trasparency;

    public TransparentShape(Shape shape, int trasparency) {
        this.shape = shape;
        this.trasparency = trasparency;
    }

    @Override
    public String info() {
        return shape.info() + " has transperancy %" + trasparency;
    }

}

public class DynamicOperatorDemo {
    public static void main(String[] args) {
        Circle circle = new Circle(10);
        System.out.println(circle.info());
        ColoredShape coloredShape = new ColoredShape(new Square(20), "blue");
        System.out.println(coloredShape.info());

        TransparentShape myCircle = new TransparentShape(new ColoredShape(new Circle(5), "green"), 25);
        System.out.println(myCircle.info());
    }
}
