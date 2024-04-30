package org.example.mediator;

import io.reactivex.rxjava3.annotations.NonNull;
import io.reactivex.rxjava3.core.Observable;
import io.reactivex.rxjava3.core.Observer;
import java.util.ArrayList;
import java.util.List;

class EventBrokerMed extends Observable<Integer> {
    private List<Observer<? super Integer>> observers = new ArrayList<>();

    @Override
    protected void subscribeActual(@NonNull Observer<? super Integer> observer) {
        observers.add(observer);
    }

    public void publish(int n) {
        for (Observer<? super Integer> observer: observers) {
            observer.onNext(n);
        }
    }

}

class FootballPlayerMed {
    private int goalScore = 0;
    private EventBrokerMed broker;
    public String name;

    public FootballPlayerMed(EventBrokerMed broker, String name) {
        this.broker = broker;
        this.name = name;
    }

    public void score() {
        broker.publish(++goalScore);
    }
}

class FootbalallCoachMed {
    public FootbalallCoachMed(EventBrokerMed broker) {
        broker.subscribe(i -> {
            System.out.println("hey you scored " + i + " goals!");
        });
    }
}

public class ReactiveExtensionEventBroker {
    public static void main(String[] args) {
        EventBrokerMed broker = new EventBrokerMed();
        FootballPlayerMed footballPlayer = new FootballPlayerMed(broker, "John");
        FootbalallCoachMed footbalallCoach = new FootbalallCoachMed(broker);
        footballPlayer.score();
        footballPlayer.score();
        footballPlayer.score();
    }
}
