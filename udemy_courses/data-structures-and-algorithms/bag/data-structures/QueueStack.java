import java.util.Stack;

void main() {
    Queue q = new Queue(1);
    q.push(2);
    q.push(3);
    q.push(4);
    System.out.println(q.peek());
    System.out.println(q.pop());
    System.out.println(q.peek());
}

/**
 * Implementing Queue using Stack
 */
static class Queue {
    Stack<Integer> stack;

    Queue(int value) {
        stack = new Stack<>();
        stack.add(value);
    }

    public void push(int value) {
        stack.add(value);
    }

    public int peek() {
        return stack.getFirst();
    }

    public int pop() {
        return stack.removeFirst();
    }

    public boolean isEmpty() {
        return stack.isEmpty();
    }
}
