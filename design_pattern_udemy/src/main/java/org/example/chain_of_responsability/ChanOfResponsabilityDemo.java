package org.example.chain_of_responsability;

//Method chain
class Creature {
    public String name;
    public int attack, defense;

    public Creature(String name, int attack, int defense) {
        this.name = name;
        this.attack = attack;
        this.defense = defense;
    }

    @Override
    public String toString() {
        return "Creature [name=" + name + ", attack=" + attack + ", defense=" + defense + "]";
    }

}

// the reason why we're creating a creature modifier is because we want to have
// a starting point upon which we add all those next elements to traverse.
class CreatureModifier {
    protected Creature creature;
    protected CreatureModifier next;

    public CreatureModifier(Creature creature) {
        this.creature = creature;
    }

    public void add(CreatureModifier cm) {
        if (next != null)
            next.add(cm);
        else
            next = cm;

    }

    // So here is handle and we're going to basically check that the modifier is in
    // fact available. If it is available, then what we're going to do is we're
    // going to say that if next is not equal to null, we're going to call handle.
    public void handle() {
        if (next != null)
            next.handle();
    }
}

class DoubleAttackmodifier extends CreatureModifier {

    public DoubleAttackmodifier(Creature creature) {
        super(creature);
    }

    @Override
    public void handle() {
        System.out.println("Doubling " + creature.name + "'s attack");
        creature.attack *= 2;
        super.handle(); // is designed specifically for the traversal of the entire chain of
                        // responsibility.
    }

}

class IncreaseDefenseModifier extends CreatureModifier {

    public IncreaseDefenseModifier(Creature creature) {
        super(creature);
    }

    @Override
    public void handle() {
        System.out.println("Increasing " + creature.name + "'s defense");
        creature.defense *= 3;
        super.handle();
    }
}

// how to actually disrupt the chain of responsibility and how to cancel it
// outright. So all the modifiers are inapplicable to that goblin. As soon as
// apply this modifier all the other bonuses on the creature are disabled
class NoBonusesModifier extends CreatureModifier {

    public NoBonusesModifier(Creature creature) {
        super(creature);
    }

    @Override
    public void handle() { // The chain of responsability is cut
        System.out.println("No bonuses can be applied");
    }

}

public class ChanOfResponsabilityDemo {
    public static void main(String[] args) {
        Creature goblin = new Creature("goblin", 2, 2);
        System.out.println(goblin);
        CreatureModifier root = new CreatureModifier(goblin);

        root.add(new NoBonusesModifier(goblin));
        System.out.println("Lets double goblins attack...");
        root.add(new DoubleAttackmodifier(goblin));
        System.out.println("Lets increase golbins defense");
        root.add(new IncreaseDefenseModifier(goblin));
        root.handle();
        System.out.println(goblin);
    }
}
