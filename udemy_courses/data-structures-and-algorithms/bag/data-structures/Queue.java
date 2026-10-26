void main() {
    Queue q = new Queue(3);
    q.enqueue(5);
    q.enqueue(6);
    q.enqueue(10);
}

/**
 * Queue implemented with LinkedList
 */
static class Queue {
    private Node first;
    private Node last;
    int length;

    Queue(int value) {
        Node node = new Node(value);
        this.first = node;
        this.last = node;
        this.length = 1;
    }

    static class Node {
        int value;
        Node next;

        Node(int value) {
            this.value = value;
            this.next = null;
        }
    }

    public int peek() {
        if (length == 0)
            assert false : "There are no more elements";
        Node tmp = first;
        first = first.next;
        return tmp.value;
    }

    public void enqueue(int value) {
        Node newNode = new Node(value);
        if (length == 0) {
            this.first = newNode;
            this.last = newNode;
        } else {
            last.next = newNode;
            last = newNode;
        }
        length++;
    }

    public int dequeue() {
        if (length == 0)
            throw new UnsupportedOperationException();
        System.out.println(length);
        Node tmp = first;
        first = first.next;
        length--;
        return tmp.value;
    }

}
