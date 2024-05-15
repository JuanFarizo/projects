use std::io;

fn main() {
    println!("Guess the number!");
    println!("Please input your guess: ");

    let mut guess = String::new();

    io::stdin()
        .read_line(&mut guess) // The string argument needs to be mutable so the method can change the string’s content.
        .expect("Failed to read line");
    println!("You guessed: {guess}");
}
