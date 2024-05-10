package org.example.recursion;

/**
 * There are 3 rods and several disks of different size which can slide onto any rod
 * The puzzle starts with the disks (that are in ascending order) on the first rod
 * The aim of the problem is to move all the plates from the first rot to the last rod (and
 * there are some rules)
 * The minimum number of moves required to solve the towers of Hanoi problem is O(2^N-1)
 * which is O(2^N) exponential running time
 * Rules:
 * 1. Only a single disk (plate) can be moved at a time
 * 2. Each move consist of taking the upper disk from one of the stacks and placing it on top of another stack
 * 3. No disk may be placed on top of a smaller plate - and a disk can only be moved if it is the uppermost disk on the stack
 */

public class TowersOfHanoi {
    public static int moves = 0;
    public static void solve(int disk, char source, char middle, char destination) {

        // 0 represent the smaller plate, 1 represent middle and 2 represent largest plate
        if (disk == 0) {
            System.out.println(
                   "Move: "  + ++moves + " Plat: " + disk + " form " + source + " to " + destination);
            return;
        }
        // We move n-1 plate to the middle rod - to be able to move
        // the largest one to the destination (last) rod
        solve(disk - 1, source, destination, middle);
        // We move the large plate to the destination
        // We call this method recursively so this is not always the larges plate
        System.out.println(
                "Move: "  + ++moves + " Plate " + disk + " from " + source + " to " + destination);
        // We move n-1 plates from middle to the destination (with the help of the first rod)
        solve(disk-1, middle, source, destination);
    }
}
