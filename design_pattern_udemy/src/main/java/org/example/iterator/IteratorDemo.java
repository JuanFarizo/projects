package org.example.iterator;

import java.util.Iterator;
import java.util.function.Consumer;

class NodeIterator<T> {
    public T value;
    public NodeIterator<T> left, right, parent;

    public NodeIterator(T value) {
        this.value = value;
    }

    public NodeIterator(T value, NodeIterator<T> left, NodeIterator<T> right) {
        this.value = value;
        this.left = left;
        this.right = right;

        left.parent = right.parent = this;
    }
}

class InOrderIterator<T> implements Iterator<T> {

    private NodeIterator<T> current, root;
    private boolean yieldedStart;

    public InOrderIterator(NodeIterator<T> root) {
        this.current = this.root = root;
        while (current.left != null) {
            current = current.left;
        }
    }

    private boolean hasRightmostParent(NodeIterator<T> node) {
        if (node.parent == null)
            return false;
        else {
            return (node == node.parent.left) || hasRightmostParent(node.parent);
        }
    }

    @Override
    public boolean hasNext() {
        return current.left != null
                || current.right != null
                || hasRightmostParent(current);
    }

    @Override
    public T next() {
        if(!yieldedStart) {
            yieldedStart = true;
            return  current.value;
        }
        if(current.right != null) {
            current = current.right;
            while (current.left != null) {
                current = current.left;
            }
        } else {
            NodeIterator<T> p = current.parent;
            while (p!= null && current == p.right) {
                current = p;
                p = p.parent;
            }
            current = p;
        }
        return current.value;
    }
}
class BinaryTreeIterable<T> implements Iterable<T> {
    private NodeIterator<T> root;

    public BinaryTreeIterable(NodeIterator<T> root) {
        this.root = root;
    }

    @Override
    public Iterator<T> iterator() {
        return new InOrderIterator<>(root);
    }

    @Override
    public void forEach(Consumer<? super T> action) {
        for(T item: this) {
            action.accept(item);
        }
    }
}

public class IteratorDemo {
    public static void main(String[] args) {
        NodeIterator<Integer> root = new NodeIterator<>(1, new NodeIterator<>(2), new NodeIterator<>(3));
        InOrderIterator<Integer> iterator = new InOrderIterator<>(root);
        while (iterator.hasNext()) {
            System.out.print("iterator " + iterator.next() + ",");
        }
        System.out.println(" ");
        BinaryTreeIterable<Integer> bt = new BinaryTreeIterable<>(root);
        for (int n: bt) {
            System.out.print("for "  + n + ",");
        }
    }

}
