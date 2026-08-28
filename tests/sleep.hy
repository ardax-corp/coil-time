// sleep_ms: zero succeeds, negative is InvalidInput.
use time::{sleep_ms, TimeError};

test("sleep_ms zero") {
    match sleep_ms(0) {
        Result::Ok(_) => {},
        Result::Err(_) => panic "sleep_ms 0",
    };
}

test("sleep_ms negative is InvalidInput") {
    match sleep_ms(-1) {
        Result::Ok(_) => panic "expected InvalidInput",
        Result::Err(e) => match e {
            TimeError::InvalidInput => {},
            _ => panic "wrong error",
        },
    };
}
