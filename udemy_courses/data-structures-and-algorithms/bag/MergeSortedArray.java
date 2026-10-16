import java.util.Arrays;
import java.util.stream.IntStream;

public class MergeSortedArray {
    public static void main(String[] args) {
        int[] arr1 = {0, 3, 4, 31};
        int[] arr2 = {4, 6, 30};
        int[] sol = mergeSortedArrays(arr2, arr1);
        System.out.println("Primitive array solution");
        System.out.println(Arrays.toString(sol));
        mergeSortedArrStreamSol(arr1, arr2);
    }

    private static void mergeSortedArrStreamSol(int[] arr1, int[] arr2) {
        IntStream stream1 = Arrays.stream(arr1);
        IntStream stream2 = Arrays.stream(arr2);
        IntStream sorted = IntStream.concat(stream1, stream2).sorted();
        System.out.println("Arr Stream solution");
        System.out.println(Arrays.toString(sorted.toArray()));
    }

    private static int[] mergeSortedArrays(int[] arr1, int[] arr2)
    {
        int[] solution = new int[arr1.length + arr2.length];
        int indexSol = 0, cursor1 = 0, cursor2 = 0;
        while(cursor1 < arr1.length &&
              cursor2 < arr2.length)
        {
            if(arr1[cursor1] <= arr2[cursor2])
            {
                solution[indexSol] = arr1[cursor1];
                cursor1++;
            }
            else
            {
                solution[indexSol] = arr2[cursor2];
                cursor2++;
            }
            indexSol++;
        }

        AddRemainingItems(arr1, arr2, solution, indexSol, cursor1, cursor2);
        return solution;
    }

    private static void AddRemainingItems(int[] arr1, int[] arr2, int[] solution, int indexSol, int cursor1, int cursor2) {
        if(cursor1 < arr1.length)
        {
            while(cursor1 < arr1.length)
            {
                solution[indexSol] = arr1[cursor1];
                cursor1++;
                indexSol++;
            }
        }
        else
        {
            while(cursor2 < arr2.length)
            {
                solution[indexSol] = arr2[cursor2];
                cursor2++;
                indexSol++;
            }
        }
    }

}
