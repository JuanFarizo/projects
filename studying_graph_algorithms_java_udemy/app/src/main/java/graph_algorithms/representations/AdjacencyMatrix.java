package graph_algorithms.representations;

public class AdjacencyMatrix {

    private static int[][] adjacencyMatrix = {
            { 0, 2, 4, 0 },
            { 0, 0, 0, 3 },
            { 0, 0, 0, 0 },
            { 0, 0, 0, 0 }
    };

    public static void main(String[] args) {
        // Find all edges
        for (int i = 0; i < adjacencyMatrix.length; i++) {
            for (int j = 0; j < adjacencyMatrix.length; j++) {
                if (adjacencyMatrix[i][j] != 0)
                    System.out.println("Edge with weight: " + adjacencyMatrix[i][j]);
            }
        }

        // Look up for specific vertices O(1)
        System.out.println(adjacencyMatrix[0][2]);
    }
}
