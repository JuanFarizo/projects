void main() {
    IO.println(recursiveFibonacci(8));
}

private static int recursiveFactorial(int num) {
    if (num == 2)
        return 2;
    return num * recursiveFactorial(num - 1);
}

// Given a number N return the index value of  the Fibonacci
// sequence, where the sequence is: 0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144...
private static int recursiveFibonacci(int num) { // O(2^n)
    if (num < 2)
        return num;
    return recursiveFibonacci(num - 1) + recursiveFibonacci(num - 2);
}
