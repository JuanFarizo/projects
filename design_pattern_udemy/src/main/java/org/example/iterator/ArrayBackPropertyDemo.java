package org.example.iterator;

//We are now going to take a look at an approach called array backed properties.
//Now, just as a reminder, a property is nothing more than a field plus a getter and a setter.
//So that's the terminology.

import java.util.Iterator;
import java.util.Spliterator;
import java.util.function.Consumer;
import java.util.stream.IntStream;

class SimpleCreatureIterator {
    private int strength, agility, intelligence;

    public int max() {
        return Math.max(strength, Math.max(agility, intelligence));
    }

    public int sum() {
        return strength + agility + intelligence;
    }

    public double average() {
        return sum() / 3.0;
    }

    public int getStrength() {
        return strength;
    }

    public void setStrength(int strength) {
        this.strength = strength;
    }

    public int getAgility() {
        return agility;
    }

    public void setAgility(int agility) {
        this.agility = agility;
    }

    public int getIntelligence() {
        return intelligence;
    }

    public void setIntelligence(int intelligence) {
        this.intelligence = intelligence;
    }
}

class CreatureIterator implements Iterable<Integer> {

    private int[] stats = new int[3];

    private final int str = 0;
    private final int agi = 1;
    private final int intel = 2;

    public int getStrength() {
        return stats[str];
    }

    public void setStrength(int strength) {
        this.stats[str] = strength;
    }

    public int getAgility() {
        return stats[agi];
    }

    public void setAgility(int agility) {
        this.stats[agi] = agility;
    }

    public int getIntelligence() {
        return stats[intel];
    }

    public void setIntelligence(int intelligence) {
        this.stats[intel] = intelligence;
    }

    public int sum() {
        return IntStream.of(stats).sum();
    }

    public int max() {
        return IntStream.of(stats).max().getAsInt();
    }

    public double average() {
        return IntStream.of(stats).average().getAsDouble();
    }

    @Override
    public Iterator<Integer> iterator() {
        return IntStream.of(stats).iterator();
    }

    @Override
    public void forEach(Consumer<? super Integer> action) {
        for(int x: stats) {
            action.accept(x);
        }
    }

    @Override
    public Spliterator<Integer> spliterator() {
        return IntStream.of(stats).spliterator();
    }
}

public class ArrayBackPropertyDemo {
    public static void main(String[] args) {
        CreatureIterator creature = new CreatureIterator();
        creature.setAgility(12);
        creature.setIntelligence(13);
        creature.setStrength(17);
        System.out.println("Max stat" + " " + creature.max());
        System.out.println("Max aver" + " " + creature.average());
        System.out.println("Max sum" + " " + creature.sum());
    }
}
