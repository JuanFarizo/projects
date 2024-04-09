package org.example.composite;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Iterator;
import java.util.Spliterator;
import java.util.function.Consumer;

interface NeronContainer extends Iterable<Neuron> {
    default void connectTo(NeronContainer other) {
        if (this == other)
            return;
        for (Neuron from : this) {
            for (Neuron to : other) {
                from.out.add(to);
                to.in.add(from);
            }
        }
    }
}

class Neuron implements NeronContainer {
    public ArrayList<Neuron> in = new ArrayList<>();
    public ArrayList<Neuron> out = new ArrayList<>();

    @Override
    public void forEach(Consumer<? super Neuron> action) {
        action.accept(this);
    }

    @Override
    public Iterator<Neuron> iterator() {
        return Collections.singleton(this).iterator();
    }

    @Override
    public Spliterator<Neuron> spliterator() {
        return Collections.singleton(this).spliterator();
    }

}

class Neuronlayer extends ArrayList<Neuron> implements NeronContainer {

}

public class NeturalNetwork {
    public static void main(String[] args) {
        Neuron neuron = new Neuron();
        Neuron neuron2 = new Neuron();
        Neuronlayer layer = new Neuronlayer();
        Neuronlayer layer2 = new Neuronlayer();
        neuron.connectTo(neuron2);
        neuron.connectTo(layer);
        layer.connectTo(neuron);
        layer.connectTo(layer2);
    }
}
