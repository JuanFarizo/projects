void main() {
    BinaryTree bt = new BinaryTree();
    bt.add(6);
    bt.add(4);
    bt.add(8);
    bt.add(3);
    bt.add(5);
    bt.add(7);
    bt.add(9);
    bt.DFSinOrder(bt.root);
}

class Node {
    int value;
    Node left;
    Node right;

    public Node(int value) {
        this.value = value;
        this.left = null;
        this.right = null;
    }

}

class BinaryTree {
    Node root;

    private Node addRecursive(Node current, int value) {
        if (current == null) {
            return new Node(value);
        }

        if (value < current.value) {
            current.left = addRecursive(current.left, value);
        } else if (value > current.value) {
            current.right = addRecursive(current.right, value);
        } else {
            return current;
        }
        return current;
    }

    void DFSinOrder(Node current) {
        if (current != null) {
            DFSinOrder(current.left);
            System.out.println(current.value);
            DFSinOrder(current.right);
        }
    }

    void DFSpreOrder(Node current) {
        if (current != null) {
            System.out.println(current.value);
            DFSpreOrder(current.left);
            DFSpreOrder(current.right);
        }

    }

    void DFSpostOrder(Node current) {
        if (current != null) {
            DFSpostOrder(current.left);
            DFSpostOrder(current.right);
            System.out.println(current.value);
        }
    }

    public void add(int value) {
        root = addRecursive(root, value);
    }

    public boolean containsNode(int value) {
        return containsRecursive(root, value);
    }

    private boolean containsRecursive(Node current, int value) {
        if (current == null)
            return false;
        if (current.value == value)
            return true;

        return value > current.value ? containsRecursive(current.right, value) : containsRecursive(current.left, value);
    }
}
