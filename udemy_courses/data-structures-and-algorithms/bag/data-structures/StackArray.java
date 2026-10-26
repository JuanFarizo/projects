import java.util.ArrayList;

void main() {
    Stack stack = new Stack(1);
    stack.push(2);
    stack.push(4);
    stack.push(6);
    stack.pop();
    stack.print();
}

/**
 * Stack implementation using Array
 */
static class Stack {
    private ArrayList<Integer> arr;

    Stack(int value) {
        arr = new ArrayList<>();
        arr.add(value);
    }

    public int peek() {
        return arr.getLast();
    }

    public void push(int value) {
        arr.add(value);
    }

    public int pop() {
        return arr.removeLast();
    }

    public void print() {
        while (arr.size() > 0) {
            System.out.println(this.pop());
        }
    }
}
