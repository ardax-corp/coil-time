// Wall clock timestamp and UTC date at midnight.
use time::{timestamp, date, format, TimeError};

test("timestamp has nanos") {
    let ts = match timestamp() {
        Result::Ok(t) => t,
        Result::Err(_) => panic "timestamp",
    };
    assert(ts.nanos != 0)?;
}

test("date formats as midnight") {
    let ts = match date() {
        Result::Ok(t) => t,
        Result::Err(_) => panic "date",
    };
    let s = match format(ts, "%H:%M:%S") {
        Result::Ok(t) => t,
        Result::Err(_) => panic "format",
    };
    assert(s == "00:00:00")?;
}
