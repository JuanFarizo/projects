package demo;

// Java 25 final features only (no preview flag): instance main, pattern switch, record, sealed.
sealed interface Shape permits Circle, Square {}

record Circle(double radius) implements Shape {}

record Square(double side) implements Shape {}

class Modern {
    void main() {
        System.out.println(area(new Circle(1.0)));
    }

    static double area(Shape shape) {
        return switch (shape) {
            case Circle c -> Math.PI * c.radius() * c.radius();
            case Square s -> s.side() * s.side();
        };
    }
}
