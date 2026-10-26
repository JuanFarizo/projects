
void main() {
    Stack stack = new Stack(1);
    stack.push(2);
    stack.push(4);
    stack.push(6);
    stack.pop();
    stack.print();
}

static class Node {
    int value;
    Node next;

    public Node(int value) {
        this.value = value;
        this.next = null;
    }
}

/**
 * Stack implementation using LinkedList
 */
static class Stack {
    int length;
    Node bottom;
    Node top;

    public Stack(int value) {
        Node node = new Node(value);
        this.top = node;
        this.bottom = node;
        length = 1;
    }

    public int peek() {
        return top.value;
    }

    public void push(int value) {
        Node node = new Node(value);
        if (this.length == 0) {
            top = node;
            bottom = node;
        } else {
            Node tmp = top;
            top = node;
            top.next = tmp;
        }
        length++;
    }

    public int pop() {
        if (length == 0)
            throw new UnsupportedOperationException();
        Node tmp = top;
        top = top.next;
        length--;
        return tmp.value;
    }

    public void print() {
        Node current = top;
        while (current != null) {
            System.out.println(current.value);
            current = current.next;
        }
    }
}
