package org.example.prototype;

import java.util.Arrays;

class AddressShallowCopy implements Cloneable {
    public String streetName;
    public int houseNumber;

    public AddressShallowCopy(String streetName, int houseNumber) {
        this.streetName = streetName;
        this.houseNumber = houseNumber;
    }

    @Override
    public String toString() {
        return "Address [streetName=" + streetName + ", houseNumber=" + houseNumber + "]";
    }

    // This is not a good approach when we have to do a DeepCopy
    // This is only for a shallow copy
    @Override
    public Object clone() throws CloneNotSupportedException {
        return super.clone();
    }
}

class Person implements Cloneable {
    public String[] names;
    public AddressShallowCopy address;

    public Person(String[] names, AddressShallowCopy address) {
        this.names = names;
        this.address = address;
    }

    @Override
    public String toString() {
        return "Person [names=" + Arrays.toString(names) + ", address=" + address + "]";
    }

    @Override
    protected Object clone() throws CloneNotSupportedException {
        return new Person(
                names.clone(),
                (AddressShallowCopy) address.clone());
    }

}

class DemoHere {
    public static void main(String[] args) {
        Person person = new Person(new String[] { "Jhon", "Smith" }, new AddressShallowCopy("London", 123));
        System.out.println(person);
    }
}