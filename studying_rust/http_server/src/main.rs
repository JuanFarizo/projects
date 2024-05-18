use server::Server;
use std::env;
use website_handler::WebsiteHandler;
mod http;
mod server;
mod website_handler;
fn main() {
    let defaul_path = format!("{}/public", env!("CARGO_MANIFEST_DIR"));
    let server = Server::new("127.0.0.1:8080".to_string());
    let public_path = env::var("PUBLIC_PATH").unwrap_or(defaul_path);
    println!("public path: {}", public_path);
    server.run(WebsiteHandler::new(public_path));
}
