package org.example.mediator;

import java.util.ArrayList;
import java.util.List;

class Participant {
    private Mediator mediator;
    private int value = 0;

    public Participant(Mediator mediator) {
        // todo
        this.mediator = mediator;
        mediator.join(this);
    }

    public void setValue(int value) {
        this.value = value;
    }

    public int getValue() {
        return this.value;
    }

    public void say(int n) {
        mediator.broadcast(this, n);
    }
}

class Mediator {
    private List<Participant> participants = new ArrayList<>();

    public void join(Participant p) {
        participants.add(p);
    }

    public void broadcast(Participant source, int value) {
        participants.stream()
                .filter(p -> !source.equals(p))
                .forEach(p -> p.setValue(p.getValue() + value));
    }

    // todo
}

public class MediatorExercise {
    public static void main(String[] args) {
        Mediator mediator = new Mediator();
        Participant participant1 = new Participant(mediator);
        Participant participant2 = new Participant(mediator);
        Participant participant3 = new Participant(mediator);
        participant1.say(50);
        participant2.say(20);
        System.out.println("Participant 1 value: " + participant1.getValue());
        System.out.println("Participant 2 value: " + participant2.getValue());
        System.out.println("Participant 3 value: " + participant3.getValue());

    }
}
