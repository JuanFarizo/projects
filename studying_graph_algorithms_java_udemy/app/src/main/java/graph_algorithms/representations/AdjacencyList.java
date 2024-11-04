package graph_algorithms.representations;

public class AdjacencyList {
    public static void main(String[] args) {
        Vertex a = new Vertex("A");
        Vertex b = new Vertex("B");
        Vertex c = new Vertex("C");
        Vertex d = new Vertex("D");

        a.addNeighbor(b);
        a.addNeighbor(c);
        b.addNeighbor(d);

        a.showNeighbors();
        b.showNeighbors();
        c.showNeighbors();
        d.showNeighbors();
    }
}
