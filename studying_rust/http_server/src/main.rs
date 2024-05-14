fn main() {
    let get = Method::GET;
    let delete = Method::DELETE;

    let server = Server::new("127.0.0.1:8080".to_string());
    server.run();
}

struct Server {
    addr: String,
}
//  new is an Associated Function
impl Server {
    fn new(addr: String) -> Server {
        Server { addr: addr }
    }

    // In the case here, the run function takes ownership of the
    // entire struct because it takes ownership of the self variable
    // that points to the struct.
    // If we don't want to deallocate our structure at the end of our function
    // we can make self a reference. So in this case self does not take run,
    // does not take ownership of the struct and it can also be a mutable reference.
    fn run(&self) {
        println!("Listening on {}", self.addr)
    }
}

struct Request {
    path: String,
    query_string: String,
    method: Method,
}

enum Method {
    GET,
    DELETE,
    POST,
    PUT,
    HEAD,
    CONNECT,
    OPTIONS,
    TRACE,
    PATCH,
}
