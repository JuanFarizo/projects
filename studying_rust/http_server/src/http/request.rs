use super::method::Method;
use std::convert::TryFrom;

pub struct Request {
    path: String,
    query_string: Option<String>,
    method: Method,
}

// impl Request {
//     fn from_byte_array(buf: &[u8]) -> Result<Self, String> {}
// }

// This is a TryFrom on a byte slice for our request implies
// TryInto which is the exact opposite of TryFrom.
// For a request on a request for a byte slice.
// So instead of calling, try from on a request, we can also call try into on a byte slice.
impl TryFrom<&[u8]> for Request {
    type Error = String;

    // GET /search?name=abc&sort=1 HTTP/1.1
    fn try_from(buf: &[u8]) -> Result<Self, Self::Error> {
        unimplemented!()
    }
}

pub enum ParseError {

}                                                                               