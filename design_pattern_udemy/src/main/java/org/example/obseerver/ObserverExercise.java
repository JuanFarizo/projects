package org.example.obseerver;

import java.io.Closeable;
import java.io.IOException;
import java.util.HashMap;
import java.util.Map;
import java.util.function.Consumer;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

//---Observable Coding Exercise---
//Imagine a game where one or more rats can attack a player.
//Each individual rat has an attack  value of 1. However,
//rats attack as a swarm, so each rat's attack  value is equal
//to the total number of rats in play.
//
//Given that a rat enters play through the constructor and leaves play (dies)
//via its close()  method, please implement the Game and Rat classes so that,
//at any point in the game, the attack  value of a rat is always consistent.

class GameObExe<T> {
    int id = 0;
    Map<Integer, Consumer<T>> handlers = new HashMap<>();

    public int subscribe(Consumer<T> addHandler) {
        handlers.put(++id, addHandler);
        return id;
    }

    public void fire(T source) {
        handlers.values().forEach(h -> h.accept(source));
    }

    public void removeSubscription(T source) {
        handlers.values().forEach(h -> h.accept(source));
    }

}

class AttackPropertyChanged<T> {
    T source;

    public AttackPropertyChanged(T source) {
        this.source = source;
    }
}

class Rat implements Closeable {
    public static int swarmAttack = 0;
    private GameObExe<AttackPropertyChanged<Integer>> game;
    public int attack = 0;
    private int id;

    Consumer<AttackPropertyChanged<Integer>> handler = p -> this.attack = swarmAttack;

    public Rat(GameObExe<AttackPropertyChanged<Integer>> game) {
        swarmAttack++;
        this.game = game;
        this.id = game.subscribe(handler);
        game.fire(new AttackPropertyChanged<>(swarmAttack));
    }

    @Override
    public void close() {
        swarmAttack--;
        game.removeSubscription(new AttackPropertyChanged<>(swarmAttack));
        game.handlers.remove(id);
    }

}

public class ObserverExercise {
    public static void main(String[] args) {
        GameObExe<AttackPropertyChanged<Integer>> game = new GameObExe<>();
        Rat rat = new Rat(game);
        int attack = rat.attack;
        System.out.println(attack);
        Rat rat2 = new Rat(game);
        int attack2 = rat.attack;
        System.out.println(attack2);
    }
}

class EvaluateObEx {
    @BeforeEach
    public void setTest() {
        Rat.swarmAttack = 0;
    }

    @Test
    public void singleRatTest() {
        GameObExe game = new GameObExe();
        Rat rat = new Rat(game);
        assertEquals(1, rat.attack);
    }

    @Test
    public void twoRatTest() {
        GameObExe<AttackPropertyChanged<Integer>> game = new GameObExe();
        Rat rat = new Rat(game);
        Rat rat2 = new Rat(game);
        assertEquals(2, rat.attack);
        assertEquals(2, rat2.attack);
    }

    @Test
    public void threeRatsOneDies()
            throws IOException {
        GameObExe<AttackPropertyChanged<Integer>> game = new GameObExe<>();

        Rat rat = new Rat(game);
        assertEquals(1, rat.attack);

        Rat rat2 = new Rat(game);
        assertEquals(2, rat.attack);
        assertEquals(2, rat2.attack);

        try (Rat rat3 = new Rat(game)) {
            assertEquals(3, rat.attack);
            assertEquals(3, rat2.attack);
            assertEquals(3, rat3.attack);
        }

        assertEquals(2, rat.attack);
        assertEquals(2, rat2.attack);
    }
}