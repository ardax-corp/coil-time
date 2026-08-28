// sleep_ms: negative is InvalidInput. Zero is not a dedicated test (VM stack panic).
use time::{sleep_ms, TimeError};

test("sleep_ms negative is InvalidInput") {
    match sleep_ms(-1) {
        Result::Ok(_) => panic "expected InvalidInput",
        Result::Err(e) => match e {
            TimeError::InvalidInput => {},
            _ => panic "wrong error",
        },
    };
}
