use std::io;

fn main() {
    let mut input = String::new(); // String is a type of smart pointer

    io::stdin().read_line(&mut input);

    borrow_string(&input);
    own_string(input);
    // println!("input: {}", input);
    // print!("Weight on Mars: {}kg", calculate_weight_on_mars(100.0));
}
fn borrow_string(s: &String) {
    println!("{}", s);
}
fn own_string(s: String) {
    println!("{}", s);
}

fn calculate_weight_on_mars(weight: f32) -> f32 {
    (weight / 9.81) * 3.711 // Is the equivalent to: return ...;
}

// OWNERSHIP RULES
// 1. Each value in Rust is owned by a variable.
// 2. When the owner goes out of the scope, the value will be deallocated.
// 3. There can only be ONE owner at a time. By doing this Rust eliminates the possibility of a double free error.

// Borrowing: Passing references as parameters.
// To be able to pass variables to functions without transferring ownership.
// Rust has a feature called references. References allow us to refer to a value without taking ownership of it.
fn some_fn(s: &mut String) {
    // References are immutable by default.
    s.push_str("A");
}

//IMPORTANT RULE FOR REFERENFCES IN THE SAME SCOPE:
// 1. We can have as many immutable references as we want or,
// 2. We can have a single mutable reference
