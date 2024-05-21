#![allow(dead_code)] //Turn on/off warnings
#![allow(unused_imports)]
#![allow(unused_variables)]

use std::mem;
//Entry point
fn main() {
    exercise4();
    //println!("result {}", exercise3());
}
/*
A palindrome is a word, verse, or sentence that reads the same backward or forward,
such as 'Able was I ere I saw Elba,' or a number like 1881.

Write a function named is_palindrome() that checks whether a given string is a palindrome or not.
The function should take a string as input and return a boolean value indicating whether the string is a palindrome or not.
*/
fn exercise4() {
    let input = String::from("1211");
    println!(
        "It is {:?} that the given string is palindrome",
        palindrome(input)
    );
}
fn palindrome(input: String) -> bool {
    input.
    /* Your Code here */
    false
}

/*
This question involves writing code to analyze the production of an assembly line in a car factory.
The assembly line has different speeds, ranging from 0 (off) to 10 (maximum).
At the lowest speed of 1, the assembly line produces a total of 221 cars per hour.
The production rate increases linearly with the speed,
meaning that a speed of 4 produces 4 * 221 = 884 cars per hour.

However, higher speeds increase the likelihood of producing faulty cars that need to be discarded.
The success rate depends on the speed, as shown in the table below:
· Speeds 1 to 4: 100% success rate.
· Speeds 5 to 8: 90% success rate.
· Speeds 9 and 10: 77% success rate.

You need to write two functions:
1. The first function, total_production(), calculates the total number of cars successfully produced without faults within a specified time given in hours. The function takes the number of hours and speed as input and returns the number of cars successfully produced.
2. The second function, cars_produced_per_minute(), calculates the number of cars successfully produced per minute. The function takes the number of hours and speed as input and returns the number of cars produced per minute.
Write the code for both functions based on the provided specifications.
*/
fn exercise3() {
    println!("{}", total_production(6, 1)); // to round the values we use i32. just ignore for mow
    println!("{}", cars_produced_per_minutes(6, 1))
}
fn total_production(hrs: u8, speed: u8) -> f32 {
    let cars = match speed {
        1..=4 => 221.0 * hrs as f32 * speed as f32,
        5..=8 => 221.0 * hrs as f32 * speed as f32 * 0.9,
        9..=10 => 221.0 * hrs as f32 * speed as f32 * 0.77,
        _ => return 0.0,
    };
    println!("cars produced {}", cars);
    cars
}
fn cars_produced_per_minutes(hours: u8, speed: u8) -> f32 {
    let per_minute: f32;
    /* Your code below this line*/
    per_minute = total_production(hours, speed) / 60.0;
    println!("cars produced per minute {}", per_minute);
    per_minute
}
/*
Write a program to find the sum of natural numbers below a given number N, where N is provided by the user.
The sum should only include numbers that are multiples of either 3 or 5.
For example, if the user enters N = 20, the multiples of 3 are 3, 6, 9, 12, 15, 18, and the multiples of 5 are 5, 10, and 15.

Please note that the value of 15 will be considered only once since it is a multiple of both 3 and 5.
The sum will be calculated as follows: 3 + 5 + 6 + 9 + 10 + 12 + 15 + 18.

Write a program that takes the user input N, performs the necessary calculations, and outputs the sum.
*/
fn exercise2() -> i32 {
    let mut n = String::new();
    std::io::stdin()
        .read_line(&mut n)
        .expect("failed to read input.");
    let n: i32 = n.trim().parse().expect("invalid input");
    let mut result = 0;

    for i in 1..=n {
        if i % 3 == 0 || i % 5 == 0 {
            result = result + i;
            println!("sum the value {} to the result  {}", i, result)
        }
    }
    result
}

/*
Write a program to find the difference between the square of the sum and the sum of the squares of the first N numbers.
N will be a user-defined input that your program will take.

For example, if the user enters the number 5, you should compute the square of the sum as (1 + 2 + 3 + 4 + 5)^2 = 225.
Next, compute the sum of the squares as (1^2 + 2^2 + 3^2 + 4^2 + 5^2) = (1 + 4 + 9 + 16 + 25) = 55.
Finally, calculate the difference as 225 - 55 = 170.
*/
fn exercise1() -> i32 {
    let mut n = String::new();
    std::io::stdin()
        .read_line(&mut n)
        .expect("failed to read input.");
    let n: i32 = n.trim().parse().expect("invalid input");

    let mut square_of_sum = 0;
    let mut sum_of_squares = 0;

    for i in 1..=n {
        square_of_sum = square_of_sum + i;
        sum_of_squares = sum_of_squares + i.pow(2);
    }

    let result = (square_of_sum.pow(2)) - sum_of_squares;
    println!("{}", result);
    result
}

fn operators() {
    //Arithmetic
    let a = 2 + 3 * 4;
    println!("a = {} before", a);
    //a = a + 1;
}

fn variables() {
    println!("Hello, world!");
    let a: u8 = 123; // u = unsigned, 8 bits, 0-255
    println!("a = {}", a); // immutable. ALl variables are declared by default immutable

    // u = unsigned 0 to 2^N-1
    // i = signed
    let mut b: i8 = 0; // Mutable variable -128 127
    println!("b = {} before", b);
    b = -13;
    println!("b = {} now", b);

    let mut c = 12456789; // i32 = 32 bits = 4 bytes
    println!("c = {} take up {} bytes before", c, mem::size_of_val(&c));
    c = -1;
    println!("c = {} take up {} bytes now", c, mem::size_of_val(&c));
    // u8, u16, u32, u64, i8, i16, i32....

    // To declare a variable of a type which is native to that processor, which is native to that operating we use:
    // Usize unsigne size
    // Isize singed size

    let d: isize = 123;
    let size_of_z = mem::size_of_val(&d);
    println!(
        "d = {} takes up {} bytes, {}-bit OS",
        d,
        size_of_z,
        size_of_z * 8
    );

    let e: char = 'x';
    println!("{} is a char, size = {} bytes", e, mem::size_of_val(&e));

    // f32 f64
    let f: f32 = 2.5;
    println!("{} is a float, size = {} bytes", f, mem::size_of_val(&f));

    let g: bool = false;
    println!("{} is a bool, size = {} bytes", g, mem::size_of_val(&g));
}

fn memory_management() {
    let a = 2;
    let result = stack_only(a);
    dbg!(result);
}
fn stack_only(b: i32) -> i32 {
    let c = 3;
    return b + c + stack_and_heal();
}
fn stack_and_heal() -> i32 {
    let d = 5;
    let e = Box::new(7);
    return d + *e;
}
