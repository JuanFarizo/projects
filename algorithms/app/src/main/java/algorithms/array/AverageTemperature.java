package algorithms.array;

import java.util.Scanner;

public class AverageTemperature {


    public static void main(String[] args) {
        Scanner cl = new Scanner(System.in);
        System.out.println("How many days");
        int days = cl.nextInt();
        int[] daysTemp = new int[days];
        int sumTemp = 0;
        for (int i = 0; i < days; i++) {
            System.out.println("Temp day: " + i);
            int dayTemp = cl.nextInt();
            sumTemp += dayTemp;
            daysTemp[i] = dayTemp;
        }
        float avera = sumTemp / days;
        System.out.println("Average temperature: " + avera);
        int numOfDaysAboveAverage = 0;
        for (int i = 0; i < days; i++) {
            if (avera < daysTemp[i]) numOfDaysAboveAverage++;
        }
        System.out.println("Numbers of days above average: " + numOfDaysAboveAverage);
    }

}
