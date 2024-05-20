use rand::Rng;
use std::cmp::Ordering;
use std::io;

fn main() {
    let string_algo = "some string";
    let secret_number = rand::thread_rng().gen_range(1..=100);
    let mut chances: u8 = 0;
    loop {
        println!("Guess the number!");
        println!("Please input your guess: ");

        let mut guess = String::new();

        io::stdin()
            .read_line(&mut guess) // The string argument needs to be mutable so the method can change the string’s content.
            .expect("Failed to read line");

        chances = chances + 1;
        if chances >= 3 {
            break;
        }

        let guess: u32 = match guess.trim().parse() {
            Ok(num) => num,
            Err(_) => continue,
        };

        match guess.cmp(&secret_number) {
            Ordering::Less => println!("Too small"),
            Ordering::Greater => println!("Too big"),
            Ordering::Equal => {
                println!("You win");
                break;
            }
        }
    }
    println!("The Secret Number is: {secret_number}");
}
