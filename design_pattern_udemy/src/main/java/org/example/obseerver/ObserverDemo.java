package org.example.obseerver;

import java.util.ArrayList;
import java.util.List;

//For example if I want to be
//Whenever somebody sets the age, you might have some UI
//component that needs to be informed about the
class PropertyChangedEventsArgs<T> {
    public T source;
    public String propertyName;
    public Object newValue;

    public PropertyChangedEventsArgs(T source,
            String propertyName,
            Object newValue) {
        this.source = source;
        this.propertyName = propertyName;
        this.newValue = newValue;
    }
}

interface ObserverOb<T> {
    void handle(PropertyChangedEventsArgs<T> args);
}

class ObservableOb<T> {
    private List<ObserverOb<T>> observers = new ArrayList<>();

    public void subscribe(ObserverOb<T> observer) {
        observers.add(observer);
    }

    protected void propertyChanged(T source,
            String propertyName,
            Object newValue) {
        for (ObserverOb<T> o : observers) {
            o.handle(new PropertyChangedEventsArgs<>(
                    source,
                    propertyName,
                    newValue));
        }
    }
}

// Pitfall of this approach:
//However, you notice it's extending observable of person,
// which means that person cannot have a proper  base class.
class PersonOb extends ObservableOb<PersonOb> {
    private int age;

    public int getAge() {
        return age;
    }

    public void setAge(int age) {
        if (this.age == age)
            return;
        this.age = age;
        propertyChanged(this, "age", age);
    }
}

public class ObserverDemo implements ObserverOb<PersonOb> {
    public static void main(String[] args) {
        new ObserverDemo();
    }

    public ObserverDemo() {
        PersonOb person = new PersonOb();
        person.subscribe(this);
        for (int i = 0; i < 4; i++) {
            person.setAge(i);
        }
    }

    @Override
    public void handle(PropertyChangedEventsArgs<PersonOb> args) {
        System.out.println("The class " + args.source.getClass().getSimpleName()
                + " change, the property " + args.propertyName + " new value is: "
                + args.newValue.toString());
    }
}
