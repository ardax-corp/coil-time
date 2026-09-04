use time::{epoch};
use io::{stdout, write};
use string::{format, to_bytes};

fn epoch_ok() -> int {
    return match epoch() {
        Result::Ok(t) => t.nanos(),
        Result::Err(e) => -1,
    };
}

fn main() {
    write(stdout(), to_bytes(format("%i", epoch_ok())));
}
