// In this file we can actually specify the public interface for our model.

pub use method::Method;
pub use request::ParseError;
pub use request::Request;

mod method;
pub mod query_string;
mod request;
