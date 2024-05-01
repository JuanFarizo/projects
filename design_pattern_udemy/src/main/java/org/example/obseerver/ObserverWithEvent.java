package org.example.obseerver;

import java.util.HashMap;
import java.util.Map;
import java.util.function.Consumer;

/*
* So the takeaway  is that instead of forcing people to implement observer of an observable
of T, what you can do is you can just encapsulate the idea of an event.
So an event is essentially just a container of subscriptions.
And whenever you need to fire an event, you just go through every single subscription, and you fire
on it and let the handlers actually receive the argument and do something with it.
* */

/*
So an event is going to encapsulate this idea of something
happening, and you're going to be able to subscribe to this
event to get notifications.
* */
class Event<TArgs> { // TArgs and that's representing the actual data that's being fired as the event gets fired.
    private int count = 0;
    private Map<Integer, Consumer<TArgs>> handlers = new HashMap<>();

    //    When adding a handler, I want to give some sort of memento
    //    back to whoever is subscribing to this event
    //    in order to be able to disconnect from the event.
    public SubscriptionOb addHandler(Consumer<TArgs> handler) {
        int i = count;
        handlers.put(count++, handler);
        return new SubscriptionOb(this, i);
    }

    //firing the event to notify all the consumers that something happened.
    public void fire(TArgs args) {
        for (Consumer<TArgs> handler : handlers.values()) {
            handler.accept(args);
        }
    }

    //    implement AutoClosable The reason I'm doing this is quite simply so that you can put it
    //    into a try with resources kind of construct and get it to work, because essentially you might want
    //    a subscription to only last for a certain amount of time and that's exactly what we're going to do here.
    public class SubscriptionOb implements AutoCloseable {
        private Event<TArgs> event;
        private int id; // Key of the Map

        public SubscriptionOb(Event<TArgs> event, int i) {
            this.event = event;
            this.id = i;
        }

        @Override
        public void close() {
            event.handlers.remove(id);
        }
    }

}

class PropertyChangedEventsArgs2 {
    public Object source;
    public String propertyName;

    public PropertyChangedEventsArgs2(Object source,
            String propertyName) {
        this.source = source;
        this.propertyName = propertyName;
    }
}

//Now imagine you have a massive tree of different properties dependent on one another.
//This approach that I'm showing here is not going to work.
//It simply does not scale
class PersonObEv {
    public Event<PropertyChangedEventsArgs2> propertyChange = new Event<>();
    private int age;

    public int getAge() {
        return age;
    }

    public void setAge(int age) {
        if (this.age == age)
            return;
        this.age = age;
        propertyChange.fire(new PropertyChangedEventsArgs2(this, "age"));
    }
}

public class ObserverWithEvent {
    public static void main(String[] args) {
        PersonObEv person = new PersonObEv();
        Event<PropertyChangedEventsArgs2>.SubscriptionOb sub = person.propertyChange.addHandler(
                x -> {
                    System.out.println(
                            "Person's " + x.propertyName + " has changed");
                });
        person.setAge(17);
        person.setAge(18);
        sub.close();
        person.setAge(19);
    }
}
