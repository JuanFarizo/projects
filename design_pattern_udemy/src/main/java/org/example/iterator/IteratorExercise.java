package org.example.iterator;

import java.util.Iterator;
import java.util.function.Consumer;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

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

    @SuppressWarnings("unchecked")
    public Iterator<NodeEx<T>> preOrder() {
        BinaryTreeIteratorEx<NodeEx<T>> bt = (BinaryTreeIteratorEx<NodeEx<T>>) new BinaryTreeIteratorEx<>(this);
        return bt.iterator();
    }
}

class PreOrderIterator<T> implements Iterator<T> {
    private NodeEx<T> current, root;
    private boolean yieldedStart;

    public PreOrderIterator(NodeEx<T> root) {
        this.current = this.root = root;
    }

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
        } else if (current.right == null) {
            NodeEx<T> p = current.parent.parent;
            if (p != null) {
                current = p.right;
            }
        } else {
            NodeEx<T> p = current.parent;
            if (p != null) {
                current = p.right;
            }
        }

        return current.value;
    }

    private boolean hasSomething(NodeEx<T> node) {
        if (node.parent == null)
            return false;
        else {
            return (node == node.parent.left) || hasSomething(node.parent);
        }
    }
}

class BinaryTreeIteratorEx<T> implements Iterable<T> {
    private NodeEx<T> root;

    public BinaryTreeIteratorEx(NodeEx<T> root) {
        this.root = root;
    }

    @Override
    public Iterator<T> iterator() {
        return new PreOrderIterator<>(root);
    }

    @Override
    public void forEach(Consumer<? super T> action) {
        for (T item : this) {
            action.accept(item);
        }
    }
}

public class IteratorExercise {
    public static void main(String[] args) {

    }
}

class EvaluateExIterator {
    @Test
    public void test() {
        NodeEx<Character> node = new NodeEx<>('a', new NodeEx<>('b', new NodeEx<>('c'), new NodeEx<>('d')), new NodeEx<>('e'));
        StringBuilder sb = new StringBuilder();
        BinaryTreeIteratorEx<Character> iterator = new BinaryTreeIteratorEx<>(node);
        Iterator<NodeEx<Character>> it = node.preOrder();
//        while (it.hasNext()) {
//            sb.append(it.next().value);
//        }
        for (Character c: iterator) {
            sb.append(c);
        }
        assertEquals("abcde", sb.toString());
    }
}
