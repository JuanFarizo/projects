package org.example.template_method;

class CreatureTME
{
    public int attack, health;

    public CreatureTME(int attack, int health)
    {
        this.attack = attack;
        this.health = health;
    }
}

abstract class CardGameTME
{
    public CreatureTME[] creatureTMES;

    public CardGameTME(CreatureTME[] creatureTMES)
    {
        this.creatureTMES = creatureTMES;
    }

    // returns -1 if no clear winner (both alive or both dead)
    public int combat(int creature1, int creature2)
    {
        CreatureTME first = creatureTMES[creature1];
        CreatureTME second = creatureTMES[creature2];
        hit(first, second);
        hit(second, first);
        return winner(creature1, creature1);
        // todo: determine who won and return either creature1 or creature2
    }

    private int winner(int first, int second) {
        if((creatureTMES[first].health <= 0 && creatureTMES[second].health <= 0) || (creatureTMES[first].health > 0 && creatureTMES[second].health > 0)) return -1;
        if(creatureTMES[first].health <= 0) return second;
        else return first;
    }

    // attacker hits other creature
    protected abstract void hit(CreatureTME attacker, CreatureTME other);
}

class TemporaryCardDamageGameTME extends CardGameTME
{
    public TemporaryCardDamageGameTME(CreatureTME [] creatures) {
        super(creatures);
    }
    @Override
    public void hit(CreatureTME attacker, CreatureTME other) {
        if(attacker.attack >= other.health) other.health = 0;
    }
    // todo
}

class PermanentCardDamageGameTME extends CardGameTME
{
    public PermanentCardDamageGameTME(CreatureTME[] creatureTMES) {
        super(creatureTMES);
    }

    @Override
    protected void hit(CreatureTME attacker, CreatureTME other) {
        other.health -= attacker.attack;
    }
    // todo
}


public class TemplateMethodExercise {
    public static void main(String[] args) {

    }
}
