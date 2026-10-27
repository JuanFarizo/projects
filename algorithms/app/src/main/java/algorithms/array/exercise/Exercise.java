package algorithms.array.exercise;

import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

public class Exercise {

    // Write a function called middle that takes an array and returns a new array
    // that contains all but the first and last elements.
    public static void main(String[] args) {
        System.out.println(
                Arrays.toString(findTopTwoScores(new int[] { 84, 85, 86, 87, 85, 90, 85, 83, 23, 45, 84, 1, 2, 0 })));
    }

    public static int[] middle(int[] array) {
        if (array.length <= 2)
            return new int[0];
        int[] newArr = new int[array.length - 2];
        for (int i = 1; i < array.length - 1; i++) {
            newArr[i - 1] = array[i];
        }
        return newArr;
    }

    public static int sumDiagonalElements(int[][] array) {
        /*
         * {1,2,3}
         * {4,5,6}
         * {7,8,9}
         */
        if (array[0].length != array.length)
            return 0;
        int sum = 0;
        for (int i = 0; i < array[0].length; i++) {
            sum += array[i][i];
        }
        return sum;
    }

    public static int[] findTopTwoScores(int[] array) {
        if (array.length < 2)
            return null;
        int first = Integer.MIN_VALUE;
        int second = Integer.MIN_VALUE;
        for (int i = 0; i < array.length; i++) {
            // If arra[i] > first
            if (array[i] > first) {
                second = first;
                first = array[i];
                continue;
            } else if (array[i] > second) {
                second = array[i];
            }
        }
        return new int[] { first, second };
    }

    static int findMissingNumberInArray(int[] arr) {
        int n = arr.length + 1;
        int expectedSum = (n * (n + 1)) / 2;
        int actualSum = 0;
        for (int number : arr) {
            actualSum += number;
        }
        return expectedSum - actualSum;
    }

    public static int[] removeDuplicates(int[] arr) {
        Set<Integer> unique = new HashSet<>();
        for (int i = 0; i < arr.length; i++) {
            unique.add(arr[i]);
        }
        int[] solution = new int[unique.size()];
        int i = 0;
        for (Integer num : unique) {
            solution[i] = num;
            i++;
        }        
        return solution;
    }

}
