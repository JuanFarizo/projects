package org.example.chain_of_responsability;

import java.util.HashMap;
import java.util.Map;
import java.util.function.Consumer;

//COR + Observer + Mediator + (-)Memento

//CQS Command Query Separation
class Event<Args> {
    // Observer (Suscribe an event, Unsuscribe an event, or Fire an event)
    private int index = 0;

    private Map<Integer, Consumer<Args>> handlers = new HashMap<>(); // bunch of subscribers or handlers. These are
                                                                     // going to be effectively functions which handle
                                                                     // whenever a particular event is fired and it's
                                                                     // provided a certain number of arguments

    public int suscribe(Consumer<Args> handler) {
        int i = index;
        handlers.put(index++, handler);
        return i;
    }

    public void unsiscribe(int key) {
        handlers.remove(key);
    }

    public void fire(Args args) {
        for (Consumer<Args> handler : handlers.values()) {
            handler.accept(args);
        }
    }
}

class Query {
    public String creatureName;

    enum Argument {
        ATTACK, DEFENSE
    }

    public Argument argument;
    public int result;

    public Query(String creatureName, Argument argument, int result) {
        this.creatureName = creatureName;
        this.argument = argument;
        this.result = result;
    }

}

// Mediator
class Game {
    // So the idea behind this is that we now have a central location where any
    // modifier can subscribe itself to queries on the creature and modify the
    // creatures, attack or defense value.

    public Event<Query> queries = new Event<>();
}

class CreatureBase {
    public Game game;
    public String name;
    public int baseAttack, baseDefense;

    public CreatureBase(Game game, String name, int baseAttack, int baseDefense) {
        this.game = game;
        this.name = name;
        this.baseAttack = baseAttack;
        this.baseDefense = baseDefense;
    }

    public int getAttack() {
        Query q = new Query(name, Query.Argument.ATTACK, baseAttack);
        game.queries.fire(q);
        return q.result;
    }

    public int getDefense() {
        Query q = new Query(name, Query.Argument.DEFENSE, baseDefense);
        game.queries.fire(q);
        return q.result;
    }

    @Override
    public String toString() {
        return "Creature [name=" + name + ", baseAttack=" + getAttack() + ", baseDefense=" + getDefense() + "]";
    }

}

class CreatureModifier {
    protected Game game;
    protected CreatureBase creature;

    public CreatureModifier(Game game, CreatureBase creature) {
        this.game = game;
        this.creature = creature;
    }

}

class DoubleAttackModifier2 extends CreatureModifier implements AutoCloseable {

    private final int token;

    public DoubleAttackModifier2(Game game, CreatureBase creature) {
        super(game, creature);
        token = game.queries.suscribe(q -> {
            if (q.creatureName.equals(creature.name) && q.argument == Query.Argument.ATTACK)
                q.result *= 2;
        });
    }

    @Override
    public void close() {
        game.queries.unsiscribe(token);
    }
}

class IncreaseDefenseModifier2 extends CreatureModifier {

    public IncreaseDefenseModifier2(Game game, CreatureBase creature) {
        super(game, creature);
        game.queries.suscribe(q -> {
            if (q.creatureName.equals(creature.name) && q.argument == Query.Argument.DEFENSE)
                q.result += 3;
        });
    }

}

public class BrokerChainDemo {
    public static void main(String[] args) {
        Game game = new Game();
        CreatureBase goblin = new CreatureBase(game, "Strong goblin", 2, 2);
        System.out.println(goblin);
        IncreaseDefenseModifier2 idm = new IncreaseDefenseModifier2(game, goblin);
        DoubleAttackModifier2 dam = new DoubleAttackModifier2(game, goblin);
        try (dam) {
            System.out.println(goblin);
        }
        System.out.println(goblin);
    }
}
