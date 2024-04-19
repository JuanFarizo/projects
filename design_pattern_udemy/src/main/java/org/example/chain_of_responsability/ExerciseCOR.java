package org.example.chain_of_responsability;

import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

abstract class CreatureExercise {
    protected GameExercise game;
    protected int baseAttack, baseDefense;

    public CreatureExercise(GameExercise game, int baseAttack, int baseDefense) {
        this.game = game;
        this.baseAttack = baseAttack;
        this.baseDefense = baseDefense;
    }

    public abstract int getAttack();

    public abstract int getDefense();

    public abstract void query(Object source, StatQuery sq);
}

class GoblinExercise extends CreatureExercise {

    public GoblinExercise(GameExercise game, int attackBase, int defenseBase) {
        super(game, attackBase, defenseBase);
    }

    public GoblinExercise(GameExercise game) {
        super(game, 1, 1);
    }

    @Override
    public int getAttack() {
        StatQuery q = new StatQuery(Statistic.ATTACK);
        for (CreatureExercise creature : game.creatures) {
            creature.query(this, q);
        }
        return q.result;
    }

    @Override
    public int getDefense() {
        StatQuery q = new StatQuery(Statistic.DEFENSE);
        for (CreatureExercise c : game.creatures)
            c.query(this, q);
        return q.result;
    }

    @Override
    public void query(Object source, StatQuery sq) {
        if (source == this) {
            switch (sq.statistic) {
                case ATTACK:
                    sq.result += baseAttack;
                    break;
                case DEFENSE:
                    sq.result += baseDefense;
                    break;
            }
        } else if (sq.statistic == Statistic.DEFENSE) {
            sq.result++;
        }

    }
}

class GoblinKingExercise extends GoblinExercise {

    public GoblinKingExercise(GameExercise game) {
        super(game, 3, 3);
    }

    @Override
    public void query(Object source, StatQuery sq) {
        if (source != this && sq.statistic == Statistic.ATTACK)
            sq.result++; // every goblin gets +1 attack
        else
            super.query(source, sq);
    }
}

enum Statistic {
    ATTACK, DEFENSE
}

class StatQuery {
    public Statistic statistic;
    public int result;

    public StatQuery(Statistic statistic) {
        this.statistic = statistic;
    }
}

class GameExercise {
    public List<CreatureExercise> creatures = new ArrayList<>();
}

public class ExerciseCOR {

    public static void main(String[] args) {
        GameExercise game = new GameExercise();
        GoblinExercise goblin = new GoblinExercise(game);
        game.creatures.add(goblin);
        for (CreatureExercise creature : game.creatures) {
            System.out.println(creature.toString());
        }
    }
}


class ExerciseCORTest {
    @Test
    public void Test() {
        GameExercise game = new GameExercise();
        GoblinExercise goblin = new GoblinExercise(game);
        game.creatures.add(goblin);

        assertEquals(1, goblin.getAttack());
        assertEquals(1, goblin.getDefense());

        GoblinExercise goblin2 = new GoblinExercise(game);
        game.creatures.add(goblin2);

        assertEquals(1, goblin.getAttack());
        assertEquals(2, goblin.getDefense());

        GoblinKingExercise goblin3 = new GoblinKingExercise(game);
        game.creatures.add(goblin3);

        assertEquals(2, goblin.getAttack());
        assertEquals(3, goblin.getDefense());
    }
}