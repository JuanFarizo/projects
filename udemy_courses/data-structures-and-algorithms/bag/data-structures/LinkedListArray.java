import java.util.ArrayList;
import java.util.List;

void main() {
    test();
}

static class Node<T> {
    T value;
    Node<T> next;

    public Node(T value) {
        this.value = value;
        this.next = null;
    }
}

static class Arr<T> {
    private Node<T> root;

    public Arr(T value) {
        this.root = new Node<T>(value);
    }

    public void add(T value) {
        if (root == null)
            return;
        Node<T> current = root;
        while (current.next != null) {
            current = current.next;
        }
        current.next = new Node<T>(value);
    }

    public T pop() {
        Node<T> current = root;
        Node<T> prev = root;
        while (current.next != null) {
            prev = current;
            current = current.next;
        }
        prev.next = null;
        return current.value;
    }

    public T get(int index) {
        assert index >= 0 : "Index must be positive";
        assert root != null : "There is no element to return";
        Node<T> current = root;
        for (int i = 0; i < index; i++) {
            assert current.next != null : "Out of bound";
            current = current.next;
        }
        return current.value;
    }

    public void reverse() {
        if (root.next == null) {
            return;
        }
        Node<T> prev = root;
        Node<T> current = root.next;
        Node<T> next;
        while (current.next != null) {
            next = current.next;
            current.next = prev;
            prev = current;
            current = next;
        }
        current.next = prev;
        root.next = null;
        root = current;
    }

    public void print() {
        List<T> list = new ArrayList<>();
        Node<T> current = root;
        while (current != null) {
            list.add(current.value);
            current = current.next;
        }
        IO.println(list);
    }
}

static void test() {
    Arr<Integer> arr = new Arr<>(5);
    arr.add(4);
    arr.add(7);
    arr.add(8);
    arr.add(11);
    arr.print();
    arr.reverse();
    arr.print();
}
