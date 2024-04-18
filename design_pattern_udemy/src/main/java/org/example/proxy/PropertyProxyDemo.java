package org.example.proxy;

class Property<T> {
    private T value;

    public Property(T value) {
        this.value = value;
    }

    public Property() {}

    public T getValue() {
        return value;
    }

    public void setValue(T value) {
        // Can do some loggin or configure or do some
        // sort of dependency injection to get the value, o inject default
        this.value = value;
    }

}

class Creature {
    private Property<Integer> agility = new Property<Integer>();

    // Can't use the asigne operator 
    public void setAgility(int value) {
        agility.setValue(value);
    }

    public int getAgility() {
        return agility.getValue();
    }

    @Override
    public String toString() {
        return "Creature [agility=" + agility.getValue() + "]";
    }

    
}

public class PropertyProxyDemo {
    public static void main(String[] args) {
        Creature creature = new Creature();
        creature.setAgility(12);
        System.out.println(creature);
    }
}
