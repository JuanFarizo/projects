package org.example.proxy;

interface Drivable {
    void drive();
}

class Car implements Drivable {
    protected Driver driver;

    public Car(Driver driver) {
        this.driver = driver;
    }

    @Override
    public void drive() {
        System.out.println("Car being driven");
    }

}

class Driver {
    public int age;

    public Driver(int age) {
        this.age = age;
    }
}

// Proxy for the car
class CarProxy extends Car {
    public CarProxy(Driver driver) {
        super(driver);
    }

    @Override
    public void drive() {
        if (driver.age >= 18) {
            super.drive();
        } else {
            System.out.println("Driver too young!");
        }
    }
}

public class ProxyDemo {
    public static void main(String[] args) {
        Car car = new CarProxy(new Driver(18));
        car.drive();
    }
}
