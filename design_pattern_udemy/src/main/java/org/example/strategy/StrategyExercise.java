package org.example.strategy;

import java.util.Objects;

interface DiscriminantStrategyStEx {
    double calculateDiscriminant(double a, double b, double c);
}

class OrdinaryDiscriminantStrategyStEx implements DiscriminantStrategyStEx {
    @Override
    public double calculateDiscriminant(double a, double b, double c) {
        // todo
        double powB = Math.pow(b, 2);
        return powB - 4 * a * c;
    }
}

class RealDiscriminantStrategyStEx implements DiscriminantStrategyStEx {
    @Override
    public double calculateDiscriminant(double a, double b, double c) {
        double powB = Math.pow(b, 2);
        double discriminant = powB - 4 * a * c;
        return discriminant > 0 ? discriminant : Double.NaN;
    }
}

class QuadraticEquationSolverStEx {
    private DiscriminantStrategyStEx strategy;

    public QuadraticEquationSolverStEx(DiscriminantStrategyStEx strategy) {
        this.strategy = strategy;
    }

    public PairStEx<ComplexStEx, ComplexStEx> solve(double a, double b, double c) {
        // todo
        double disc = strategy.calculateDiscriminant(a, b, c);
        ComplexStEx rootDisc = ComplexStEx.sqrt(disc);
        return new PairStEx<>(
                new ComplexStEx(-b,0).plus(rootDisc)
                        .divides(new ComplexStEx(2,0))
                        .divides(new ComplexStEx(a, 0)),
                new ComplexStEx(-b,0).minus(rootDisc)
                        .divides(new ComplexStEx(2,0))
                        .divides(new ComplexStEx(a, 0))
        );

    }
}

// complex number implementation taken from here:
// https://introcs.cs.princeton.edu/java/32class/Complex.java.html
class ComplexStEx {
    private final double re;   // the real part
    private final double im;   // the imaginary part

    // create a new object with the given real and imaginary parts
    public ComplexStEx(double real, double imag) {
        re = real;
        im = imag;
    }

    // return a string representation of the invoking Complex object
    public String toString() {
        if (im == 0)
            return re + "";
        if (re == 0)
            return im + "i";
        if (im < 0)
            return re + " - " + (-im) + "i";
        return re + " + " + im + "i";
    }

    // return abs/modulus/magnitude
    public double abs() {
        return Math.hypot(re, im);
    }

    // return angle/phase/argument, normalized to be between -pi and pi
    public double phase() {
        return Math.atan2(im, re);
    }

    // return a new Complex object whose value is (this + b)
    public ComplexStEx plus(ComplexStEx b) {
        ComplexStEx a = this;             // invoking object
        double real = a.re + b.re;
        double imag = a.im + b.im;
        return new ComplexStEx(real, imag);
    }

    // return a new Complex object whose value is (this - b)
    public ComplexStEx minus(ComplexStEx b) {
        ComplexStEx a = this;
        double real = a.re - b.re;
        double imag = a.im - b.im;
        return new ComplexStEx(real, imag);
    }

    // return a new Complex object whose value is (this * b)
    public ComplexStEx times(ComplexStEx b) {
        ComplexStEx a = this;
        double real = a.re * b.re - a.im * b.im;
        double imag = a.re * b.im + a.im * b.re;
        return new ComplexStEx(real, imag);
    }

    // return a new object whose value is (this * alpha)
    public ComplexStEx scale(double alpha) {
        return new ComplexStEx(alpha * re, alpha * im);
    }

    // return a new Complex object whose value is the conjugate of this
    public ComplexStEx conjugate() {
        return new ComplexStEx(re, -im);
    }

    // return a new Complex object whose value is the reciprocal of this
    public ComplexStEx reciprocal() {
        double scale = re * re + im * im;
        return new ComplexStEx(re / scale, -im / scale);
    }

    // return the real or imaginary part
    public double re() {
        return re;
    }

    public double im() {
        return im;
    }

    // return a / b
    public ComplexStEx divides(ComplexStEx b) {
        ComplexStEx a = this;
        return a.times(b.reciprocal());
    }

    // return a new Complex object whose value is the complex exponential of this
    public ComplexStEx exp() {
        return new ComplexStEx(Math.exp(re) * Math.cos(im),
                Math.exp(re) * Math.sin(im));
    }

    // return a new Complex object whose value is the complex sine of this
    public ComplexStEx sin() {
        return new ComplexStEx(Math.sin(re) * Math.cosh(im),
                Math.cos(re) * Math.sinh(im));
    }

    // return a new Complex object whose value is the complex cosine of this
    public ComplexStEx cos() {
        return new ComplexStEx(Math.cos(re) * Math.cosh(im),
                -Math.sin(re) * Math.sinh(im));
    }

    public static ComplexStEx sqrt(double value) {
        if (value < 0)
            return new ComplexStEx(0, Math.sqrt(-value));
        else
            return new ComplexStEx(Math.sqrt(value), 0);
    }

    // return a new Complex object whose value is the complex tangent of this
    public ComplexStEx tan() {
        return sin().divides(cos());
    }

    // a static version of plus
    public static ComplexStEx plus(ComplexStEx a, ComplexStEx b) {
        double real = a.re + b.re;
        double imag = a.im + b.im;
        ComplexStEx sum = new ComplexStEx(real, imag);
        return sum;
    }

    // See Section 3.3.
    public boolean equals(Object x) {
        if (x == null)
            return false;
        if (this.getClass() != x.getClass())
            return false;
        ComplexStEx that = (ComplexStEx) x;
        return (this.re == that.re) && (this.im == that.im);
    }

    // See Section 3.3.
    public int hashCode() {
        return Objects.hash(re, im);
    }

    public boolean isNaN() {
        return Double.isNaN(re) || Double.isNaN(im);
    }
}

class PairStEx<X, Y> {
    public final X first;
    public final Y second;

    public PairStEx(X first, Y second) {
        this.first = first;
        this.second = second;
    }
}

public class StrategyExercise {
    public static void main(String[] args) {

    }
}
