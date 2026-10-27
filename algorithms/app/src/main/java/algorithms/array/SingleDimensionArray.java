package algorithms.array;

public class SingleDimensionArray {
    int[] arr = null;

    public SingleDimensionArray(int size) {
        arr = new int[size];
    }

    public void insert(int i, int value) { // Time complexity: O(1)
        if(arr.length - 1 <= i) { // O(1)
            arr[i] = value; // O(1)
            System.out.println("Successfully inserted"); // O(1)
        }
    }

    public void travers() { // Time complexity: O(n)
        for (int i = 0; i < arr.length; i++) {
            System.out.println(arr[i]);
        }
    }

    public void find(int value) { // Time complexity O(n)
        for(int i = 0; i < arr.length; i++) {
            if (arr[i] == value) {
                System.out.println("Value find at index: " + i);
                return;
            }
        }
        System.out.println("Value not found");
    }

    // Logical deletion 
    public void deletion(int i) {
        try {
            arr[i] = Integer.MIN_VALUE;            
        } catch (IndexOutOfBoundsException e) {
            System.out.println(String.format("Index %s out of bound", i));
        }
    }
}
