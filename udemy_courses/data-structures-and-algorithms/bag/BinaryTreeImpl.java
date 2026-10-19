void main() {

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

// if the new node’s value is lower than the current node’s, we go to the left
// child
// if the new node’s value is greater than the current node’s, we go to the
// right child
// when the current node is null, we’ve reached a leaf node and we can insert
// the new node in that position
class BynaryTree {
    Node root;

    Node addRecursive(Node node, int value) {
        return null;
    }
}
