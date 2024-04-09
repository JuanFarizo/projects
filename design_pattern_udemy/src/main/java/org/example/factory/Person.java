package org.example.factory;

import java.util.concurrent.atomic.AtomicInteger;

class Person {
    public int id;
    public String name;

    public Person(int id, String name) {
        this.id = id;
        this.name = name;
    }

    @Override
    public String toString() {
        return "Person [id=" + id + ", name=" + name + "]";
    }

    public static class PersonFactory {
        private static AtomicInteger id = new AtomicInteger();

        public static Person createPerson(String name) {
            return new Person(id.getAndIncrement(), name);
        }

    }

}

class DemoExorcise {
    public static void main(String[] args) {
        Person person = Person.PersonFactory.createPerson("Pepe Trueno");
        Person person1 = Person.PersonFactory.createPerson("Pepe2 Trueno2");
        Person person2 = Person.PersonFactory.createPerson("Pepe2Trueno2");
        System.out.println(person);
        System.out.println(person1);
        System.out.println(person2);
    }
}
