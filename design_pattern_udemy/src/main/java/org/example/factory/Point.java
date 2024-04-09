package org.example.factory;

/**
 * Motivation:
 * - Object creation logic becomes too convulted
 * - Constructors is not descriptive
 * Name mandate by name of containing type
 * Cannot overload with same set of arguments with different names
 * Can turn into overloading hell
 * - Wholesale object creation (non-piecewise, unlike Builder) can be outsourced
 * to
 * A separate function (factory method)
 * That may exist in a separate class (Factory)
 * Can create hirarchy of factories with Abstract Factory
 * Definition: A component responsible solely
 * for the wholesale (not piecewise)
 * creation of obects.
 */

class Point {
    private double x, y;

    private Point(double x, double y) {
        this.x = x;
        this.y = y;
    }

    @Override
    public String toString() {
        return "Point [x=" + x + ", y=" + y + "]";
    }

    public static class FactoryPoint {
        // Factory Method
        public static Point newCartesionPoint(double x, double y) {
            return new Point(x, y);
        }

        // Factory Method
        public static Point newPolarPoint(double rho, double theta) {
            return new Point(rho * Math.cos(theta), rho * Math.sin(theta));
        }
    }

}

class Demo {
    public static void main(String[] args) {
        Point point = Point.FactoryPoint.newCartesionPoint(2, 3);
        System.out.println(point);
    }
}
