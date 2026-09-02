// date_from_period rejects month 0; epoch nanos is 0.
use time::{date_from_period, epoch, period, TimeError, Period, Timestamp};

fn must_p(Result<Period, TimeError> r) -> Period {
    return match r {
        Result::Ok(p) => p,
        Result::Err(_) => panic "period",
    };
}

test("date_from_period zero month is InvalidInput") {
    let bad = must_p(period(2024, 0, 1, 0, 0, 0, 0, 0, 0));
    match date_from_period(bad) {
        Result::Ok(_) => panic "expected InvalidInput",
        Result::Err(e) => match e {
            TimeError::InvalidInput => {},
            default => panic "wrong error",
        },
    };
}

test("epoch is zero nanos") {
    let ts = match epoch() {
        Result::Ok(t) => t,
        Result::Err(_) => panic "epoch",
    };
    assert(ts.secs() == 0)?;
    assert(ts.millis() == 0)?;
    assert(ts.micros() == 0)?;
    assert(ts.nanos() == 0)?;
}

test("date_from_period midnight") {
    let p = must_p(period(2024, 1, 1, 9, 0, 0, 0, 0, 0));
    let ts = match date_from_period(p) {
        Result::Ok(t) => t,
        Result::Err(_) => panic "date_from_period",
    };
    let e = match epoch() {
        Result::Ok(t) => t,
        Result::Err(_) => panic "epoch",
    };
    assert(ts.nanos() != e.nanos())?;
}
