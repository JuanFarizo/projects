package org.example.proxy;

class Person {
    private int age;

    public Person(int age) {
        this.age = age;
    }

    public int getAge() {
        return age;
    }

    public void setAge(int age) {
        this.age = age;
    }

    public String drink() {
        return "drinking";
    }

    public String drive() {
        return "driving";
    }

    public String drinkAndDrive() {
        return "driving while drunk";
    }
}

class ResponsiblePerson extends Person {
    private Person person;

    public ResponsiblePerson(Person person) {
        super(person.getAge());
        this.person = person;
    }

    @Override
    public String drink() {
        if (this.person.getAge() >= 18) {
            return person.drink();
        } else {
            return "too young";
        }
    }

    @Override
    public String drinkAndDrive() {
        return "dead";
    }

    @Override
    public String drive() {
        if(this.person.getAge() <= 16)
        return "too young";
        else return person.drive();
    }

}

public class ExerciseProxy {
    public static void main(String[] args) {

    }
}
