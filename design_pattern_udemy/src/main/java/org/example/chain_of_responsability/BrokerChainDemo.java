package org.example.chain_of_responsability;

import java.util.HashMap;
import java.util.Map;
import java.util.function.Consumer;

//COR + Observer + Mediator + (-)Memento

//CQS Command Query Separation
class EventBC<Args> {
    // Observer (Subscribe an event, Unsubscribe an event, or Fire an event)
    private int index = 0;

    private final Map<Integer, Consumer<Args>> handlers = new HashMap<>(); // bunch of subscribers or handlers. These are
                                                                     // going to be effectively functions which handle
                                                                     // whenever a particular event is fired and it's
                                                                     // provided a certain number of arguments

    public int subscribe(Consumer<Args> handler) {
        int i = index;
        handlers.put(index++, handler);
        return i;
    }

    public void unsubscribe(int key) {
        handlers.remove(key);
    }

    public void fire(Args args) {
        for (Consumer<Args> handler : handlers.values()) {
            handler.accept(args);
        }
    }
}

class QueryBC {
    public String creatureName;

    enum ArgumentBC {
        ATTACK, DEFENSE
    }

    public ArgumentBC argument;
    public int result;

    public QueryBC(String creatureName, ArgumentBC argument, int result) {
        this.creatureName = creatureName;
        this.argument = argument;
        this.result = result;
    }

}

// Mediator
class GameBC {
    // So the idea behind this is that we now have a central location where any
    // modifier can subscribe itself to queries on the creature and modify the
    // creatures, attack or defense value.

    public EventBC<QueryBC> queries = new EventBC<>();
}

class CreatureBaseBC {
    public GameBC game;
    public String name;
    public int baseAttack, baseDefense;

    public CreatureBaseBC(GameBC game, String name, int baseAttack, int baseDefense) {
        this.game = game;
        this.name = name;
        this.baseAttack = baseAttack;
        this.baseDefense = baseDefense;
    }

    public int getAttack() {
        QueryBC q = new QueryBC(name, QueryBC.ArgumentBC.ATTACK, baseAttack);
        game.queries.fire(q);
        return q.result;
    }

    public int getDefense() {
        QueryBC q = new QueryBC(name, QueryBC.ArgumentBC.DEFENSE, baseDefense);
        game.queries.fire(q);
        return q.result;
    }

    @Override
    public String toString() {
        return "Creature [name=" + name + ", baseAttack=" + getAttack() + ", baseDefense=" + getDefense() + "]";
    }

}

class CreatureModifierBC {
    protected GameBC game;
    protected CreatureBaseBC creature;

    public CreatureModifierBC(GameBC game, CreatureBaseBC creature) {
        this.game = game;
        this.creature = creature;
    }

}

class DoubleAttackModifierBC extends CreatureModifierBC implements AutoCloseable {

    private final int token;

    public DoubleAttackModifierBC(GameBC game, CreatureBaseBC creature) {
        super(game, creature);
        token = game.queries.subscribe(q -> {
            if (q.creatureName.equals(creature.name) && q.argument == QueryBC.ArgumentBC.ATTACK)
                q.result *= 2;
        });
    }

    @Override
    public void close() {
        game.queries.unsubscribe(token);
    }
}

class IncreaseDefenseModifierBC extends CreatureModifierBC {

    public IncreaseDefenseModifierBC(GameBC game, CreatureBaseBC creature) {
        super(game, creature);
        game.queries.subscribe(q -> {
            if (q.creatureName.equals(creature.name) && q.argument == QueryBC.ArgumentBC.DEFENSE)
                q.result += 3;
        });
    }

}

public class BrokerChainDemo {
    public static void main(String[] args) {
        GameBC game = new GameBC();
        CreatureBaseBC goblin = new CreatureBaseBC(game, "Strong goblin", 2, 2);
        System.out.println(goblin);
        IncreaseDefenseModifierBC idm = new IncreaseDefenseModifierBC(game, goblin);
        DoubleAttackModifierBC dam = new DoubleAttackModifierBC(game, goblin);
        try (dam) {
            System.out.println(goblin);
        }
        System.out.println(goblin);
    }
}
