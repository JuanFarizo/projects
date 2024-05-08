#![allow(dead_code)] //Turn on/off warnings
#![allow(unused_imports)]
#![allow(unused_variables)]

use std::mem;
//Entry point
fn main() {
    operators();
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
