package org.example.chain_of_responsability;

//Method chain
class CreatureCOR {
    public String name;
    public int attack, defense;

    public CreatureCOR(String name, int attack, int defense) {
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
class CreatureModifierCOR {
    protected CreatureCOR creature;
    protected CreatureModifierCOR next;

    public CreatureModifierCOR(CreatureCOR creature) {
        this.creature = creature;
    }

    public void add(CreatureModifierCOR cm) {
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

class DoubleAttackmodifierCOR extends CreatureModifierCOR {

    public DoubleAttackmodifierCOR(CreatureCOR creature) {
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

class IncreaseDefenseModifierCOR extends CreatureModifierCOR {

    public IncreaseDefenseModifierCOR(CreatureCOR creature) {
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
class NoBonusesModifierCOR extends CreatureModifierCOR {

    public NoBonusesModifierCOR(CreatureCOR creature) {
        super(creature);
    }

    @Override
    public void handle() { // The chain of responsability is cut
        System.out.println("No bonuses can be applied");
    }

}

public class ChanOfResponsabilityDemo {
    public static void main(String[] args) {
        CreatureCOR goblin = new CreatureCOR("goblin", 2, 2);
        System.out.println(goblin);
        CreatureModifierCOR root = new CreatureModifierCOR(goblin);

        root.add(new NoBonusesModifierCOR(goblin));
        System.out.println("Lets double goblins attack...");
        root.add(new DoubleAttackmodifierCOR(goblin));
        System.out.println("Lets increase golbins defense");
        root.add(new IncreaseDefenseModifierCOR(goblin));
        root.handle();
        System.out.println(goblin);
    }
}
