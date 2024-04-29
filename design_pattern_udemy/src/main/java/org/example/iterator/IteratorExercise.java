package org.example.iterator;

import java.util.Iterator;

class NodeEx<T> {
    public T value;
    public NodeEx<T> left, right, parent;

    public NodeEx(T value) {
        this.value = value;
    }

    public NodeEx(T value, NodeEx<T> left, NodeEx<T> right) {
        this.value = value;
        this.left = left;
        this.right = right;

        left.parent = right.parent = this;
    }

    public Iterator<NodeEx<T>> preOrder() {

        return null;
    }
}

class PreOrderIterator<T> implements Iterator<T> {
    private NodeEx<T> current, root;
    private boolean yieldedStart;

    @Override
    public boolean hasNext() {
        return current.left != null || current.right != null || hasSomething(current);
    }

    @Override
    public T next() {
        if (!yieldedStart) {
            yieldedStart = true;
            return current.value;
        }

        if (current.left != null) {
            current = current.left;
        }

        return current.value;
    }

    private boolean hasSomething(NodeEx<T> current) {
        return false;
    }
}

public class IteratorExercise {
    public static void main(String[] args) {

    }
}
