use crate::http::Request;
use std::convert::TryFrom;
use std::io::Read;
use std::net::TcpListener;

pub struct Server {
    addr: String,
}
//  new is an Associated Function
impl Server {
    pub fn new(addr: String) -> Server {
        Server { addr: addr }
    }

    // In the case here, the run function takes ownership of the
    // entire struct because it takes ownership of the self variable
    // that points to the struct.
    // If we don't want to deallocate our structure at the end of our function
    // we can make self a reference. So in this case self does not take run,
    // does not take ownership of the struct and it can also be a mutable reference.
    pub fn run(&self) {
        println!("Listening on {}", self.addr);

        let listener = TcpListener::bind(&self.addr).unwrap();

        loop {
            match listener.accept() {
                Ok((mut stream, _)) => {
                    let mut buffer = [0; 1024];
                    match stream.read(&mut buffer) {
                        Ok(_) => {
                            println!("Received a request: {}", String::from_utf8_lossy(&buffer));
                            match Request::try_from(&buffer as &[u8]) {
                                Ok(_) => {}
                                Err(e) => println!("Fail to parse a request {}", e),
                            }
                        }
                        Err(e) => println!("Failed to read from connection: {}", e),
                    }
                }
                Err(e) => println!("Fail to establish a connection: {}", e),
            }
        }
    }
}
