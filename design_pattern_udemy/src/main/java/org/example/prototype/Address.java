package org.example.prototype;

class Address {
    public String streetADress, city, country;

    public Address(String streetADress, String city, String country) {
        this.streetADress = streetADress;
        this.city = city;
        this.country = country;
    }

    // Deep copy
    public Address(Address other) {
        this(other.streetADress, other.city, other.country);
    }

    @Override
    public String toString() {
        return "Address [streetADress=" + streetADress + ", city=" + city + ", country=" + country + "]";
    }

}

class Employee {
    public String name;
    public Address address;

    public Employee(String name, Address address) {
        this.name = name;
        this.address = address;
    }

    public Employee(Employee other) {
        name = other.name;
        address = new Address(other.address);
    }

    @Override
    public String toString() {
        return "Employee [name=" + name + ", address=" + address + "]";
    }

}

class Demo {
    public static void main(String[] args) {
        Employee pepe = new Employee("pepe", new Address("123 London road", "London", "UK"));
        Employee lala = new Employee(pepe);

        lala.name = "Lala";
        System.out.println(pepe);
        System.out.println(lala);
    }
}