package org.example.iterator;

import java.util.ArrayList;
import java.util.Iterator;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class NodeSol<T> {
    public T value;
    public NodeSol<T> left, right, parent;

    public NodeSol(T value) {
        this.value = value;
    }

    public NodeSol(T value, NodeSol<T> left, NodeSol<T> right) {
        this.value = value;
        this.left = left;
        this.right = right;

        left.parent = right.parent = this;
    }

    private void traverse(NodeSol<T> current, ArrayList<NodeSol<T>> acc) {
        acc.add(current);
        if (current.left != null) {
            traverse(current.left, acc);
        }
        if (current.right != null) {
            traverse(current.right, acc);
        }
    }

    public Iterator<NodeSol<T>> preOrder() {
        ArrayList<NodeSol<T>> items = new ArrayList<>();
        traverse(this, items);
        return items.iterator();
    }
}

public class SolutionIteratorEx {
}

class EvaluateExIteratorSolution {
    @Test
    public void test() {
        NodeSol<Character> node = new NodeSol<>('a', new NodeSol<>('b', new NodeSol<>('c'), new NodeSol<>('d')), new NodeSol<>('e'));
        StringBuilder sb = new StringBuilder();
        Iterator<NodeSol<Character>> it = node.preOrder();
        while (it.hasNext()) {
            sb.append(it.next().value);
        }
        assertEquals("abcde", sb.toString());
    }
}
