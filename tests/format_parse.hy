// Format / parse roundtrip (2024-01-01 UTC).
use time::{parse, format, TimeError, Timestamp};

fn must_ts(Result<Timestamp, TimeError> r) -> Timestamp {
    return match r {
        Result::Ok(t) => t,
        Result::Err(_) => panic "timestamp",
    };
}

fn must_s(Result<string, TimeError> r) -> string {
    return match r {
        Result::Ok(s) => s,
        Result::Err(_) => panic "string",
    };
}

test("format parse roundtrip") {
    let ts = must_ts(parse("2024-01-01 00:00:00", "%Y-%m-%d %H:%M:%S"));
    let s = must_s(format(ts, "%Y-%m-%d %H:%M:%S"));
    assert(s == "2024-01-01 00:00:00")?;
    let round = must_ts(parse(s, "%Y-%m-%d %H:%M:%S"));
    assert(round.nanos == ts.nanos)?;
}

test("parse bad input is ParseError") {
    match parse("not-a-date", "%Y-%m-%d %H:%M:%S") {
        Result::Ok(_) => panic "expected ParseError",
        Result::Err(e) => match e {
            TimeError::ParseError => {},
            default => panic "wrong error",
        },
    };
}
