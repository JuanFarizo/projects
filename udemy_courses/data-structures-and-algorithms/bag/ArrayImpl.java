public class ArrayImpl {
    public static void main(String[] args) {
        test();
    }

    static class Node<T> {
        T value;
        Node<T> next;

        public Node(T value) 
        {
            this.value = value;
            this.next  = null;
        }
    }

    static class Arr<T>
    {
        private Node<T> root;

        public Arr(T value)
        {
            this.root = new Node<T>(value);
        }

        public void add(T value)
        {
            if (root == null) return;
            Node<T> current = root;
            while(current.next != null)
            {
                current = current.next;
            }
            current.next = new Node<T>(value);
        }

        public T pop()
        {
            Node<T> current = root;
            Node<T> prev = root;
            while(current.next != null)
            {
                prev = current;
                current = current.next;
            }
            prev.next = null;
            return current.value;
        }

        public T get(int index)
        {
            assert index >= 0 : "Index must be positive";
            assert root != null : "There is no element to return";
            Node<T> current = root;
            for (int i = 0; i < index; i++)
            {
                assert current.next != null  : "Out of bound";
                current = current.next;
            }
            return current.value;
        }
    }

    static void test()
    {
        Arr<Integer> arr = new Arr<>(5);
        arr.add(4);
        arr.add(7);
        System.out.println(arr.get(0));
        System.out.println(arr.get(1));
        System.out.println(arr.get(2));
        System.out.println(arr.pop());
        assert arr.get(1) == 4 : "Must be for and is: " + arr.get(1);
    }
}
