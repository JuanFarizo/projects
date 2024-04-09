package org.example.composite;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.Iterator;
import java.util.List;
import java.util.Spliterator;
import java.util.function.Consumer;

interface ValueContainer extends Iterable<Integer> {

}

class SingleValue implements ValueContainer {
    public int value;

    // please leave this constructor as-is
    public SingleValue(int value) {
        this.value = value;
    }

    @Override
    public void forEach(Consumer<? super Integer> action) {
        action.accept(Integer.valueOf(value));
    }

    @Override
    public Iterator<Integer> iterator() {
        return Collections.singleton(Integer.valueOf(value)).iterator();
    }

    @Override
    public Spliterator<Integer> spliterator() {
        return Collections.singleton(Integer.valueOf(value)).spliterator();
    }

}

class ManyValues extends ArrayList<Integer> implements ValueContainer {
}

class MyList extends ArrayList<ValueContainer> {
    // please leave this constructor as-is
    public MyList(Collection<? extends ValueContainer> c) {
        super(c);
    }

    public int sum() {
        int sum = 0;
        for (ValueContainer ele : this) {
            for (int value : ele) {
                sum += value;
            }
        }
        return sum;
    }
}

public class ExerciseComposite {
    public static void main(String[] args) {
        MyList myList = new MyList(List.of(
                new SingleValue(1),
                new SingleValue(3),
                new SingleValue(8)));
        ValueContainer vc = new SingleValue(4);
        myList.add(vc);
        ManyValues myList2 = new ManyValues();
        myList2.add(Integer.valueOf(2));
        myList.add(myList2);
        System.out.println(myList.sum());
    }
}
