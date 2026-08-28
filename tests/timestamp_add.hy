// Timestamp add one month from 2024-01-01 UTC (virtual host test).
use time::{parse, add, sub, period, format, TimeError, Timestamp, Period};

fn must_ts(Result<Timestamp, TimeError> r) -> Timestamp {
    return match r {
        Result::Ok(t) => t,
        Result::Err(_) => panic "timestamp",
    };
}

fn must_p(Result<Period, TimeError> r) -> Period {
    return match r {
        Result::Ok(p) => p,
        Result::Err(_) => panic "period",
    };
}

test("timestamp add one month") {
    let ts = must_ts(parse("2024-01-01 00:00:00", "%Y-%m-%d %H:%M:%S"));
    let month = must_p(period(0, 1, 0, 0, 0, 0, 0, 0, 0));
    let out = must_ts(add(ts, month));
    let s = match format(out, "%Y-%m-%d %H:%M:%S") {
        Result::Ok(t) => t,
        Result::Err(_) => panic "format",
    };
    assert(s == "2024-02-01 00:00:00")?;
}

test("timestamp sub one day") {
    let ts = must_ts(parse("2024-01-02 00:00:00", "%Y-%m-%d %H:%M:%S"));
    let day = must_p(period(0, 0, 1, 0, 0, 0, 0, 0, 0));
    let out = must_ts(sub(ts, day));
    let s = match format(out, "%Y-%m-%d %H:%M:%S") {
        Result::Ok(t) => t,
        Result::Err(_) => panic "format",
    };
    assert(s == "2024-01-01 00:00:00")?;
}
