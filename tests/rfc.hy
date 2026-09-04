// RFC 3339, ISO-8601, and RFC 2822 / IMF-fixdate helpers.
use time::{parse, format, parse_rfc3339, format_rfc3339, parse_iso8601, format_iso8601, parse_iso8601_date, format_iso8601_date, parse_rfc2822, format_rfc2822, parse_http_date, format_http_date, ISO8601_DATE, TimeError, Timestamp};

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

fn expect_parse_error(Result<Timestamp, TimeError> r) {
    match r {
        Result::Ok(_) => panic "expected ParseError",
        Result::Err(e) => match e {
            TimeError::ParseError => {},
            default => panic "wrong error",
        },
    };
}

test("rfc3339 roundtrip Z") {
    let ts = must_ts(parse_rfc3339("2024-01-01T00:00:00Z"));
    let s = must_s(format_rfc3339(ts));
    assert(s == "2024-01-01T00:00:00Z")?;
    let round = must_ts(parse_rfc3339(s));
    assert(round.nanos() == ts.nanos())?;
}

test("rfc3339 fractional seconds") {
    let ts = must_ts(parse_rfc3339("2024-01-01T00:00:00.123Z"));
    assert(ts.nanos() == must_ts(parse("2024-01-01 00:00:00", "%Y-%m-%d %H:%M:%S")).nanos() + 123000000)?;
    let s = must_s(format_rfc3339(ts));
    assert(s == "2024-01-01T00:00:00.123Z")?;
    let round = must_ts(parse_rfc3339(s));
    assert(round.nanos() == ts.nanos())?;
}

test("rfc3339 numeric offset") {
    let east = must_ts(parse_rfc3339("2024-01-15T12:30:00+00:00"));
    let z = must_ts(parse_rfc3339("2024-01-15T12:30:00Z"));
    assert(east.nanos() == z.nanos())?;
    let behind = must_ts(parse_rfc3339("2024-01-15T12:30:00-05:00"));
    let utc = must_ts(parse_rfc3339("2024-01-15T17:30:00Z"));
    assert(behind.nanos() == utc.nanos())?;
    assert(must_s(format_rfc3339(behind)) == "2024-01-15T17:30:00Z")?;
}

test("rfc3339 garbage is ParseError") {
    expect_parse_error(parse_rfc3339("not-a-date"));
    expect_parse_error(parse_rfc3339("2024-01-01T00:00:00"));
    expect_parse_error(parse_rfc3339("2024-01-01T00:00:00+0000"));
    expect_parse_error(parse_rfc3339("2024-13-01T00:00:00Z"));
}

test("iso8601 date roundtrip") {
    let ts = must_ts(parse_iso8601_date("2024-01-01"));
    let s = must_s(format_iso8601_date(ts));
    assert(s == "2024-01-01")?;
    let via_const = must_ts(parse("2024-01-01", ISO8601_DATE));
    assert(via_const.nanos() == ts.nanos())?;
    assert(must_s(format(ts, ISO8601_DATE)) == s)?;
    let round = must_ts(parse_iso8601_date(s));
    assert(round.nanos() == ts.nanos())?;
}

test("iso8601 datetime") {
    let z = must_ts(parse_iso8601("2024-06-08T09:10:11Z"));
    assert(must_s(format_iso8601(z)) == "2024-06-08T09:10:11Z")?;
    let naked = must_ts(parse_iso8601("2024-06-08T09:10:11"));
    assert(naked.nanos() == z.nanos())?;
    let compact = must_ts(parse_iso8601("2024-06-08T11:10:11+0200"));
    assert(compact.nanos() == z.nanos())?;
}

test("iso8601 garbage is ParseError") {
    expect_parse_error(parse_iso8601_date("2024-01-01T00:00:00Z"));
    expect_parse_error(parse_iso8601("2024-01-01"));
    expect_parse_error(parse_iso8601("nope"));
}

test("rfc2822 http-date roundtrip") {
    let ts = must_ts(parse_http_date("Mon, 01 Jan 2024 00:00:00 GMT"));
    let s = must_s(format_http_date(ts));
    assert(s == "Mon, 01 Jan 2024 00:00:00 GMT")?;
    assert(must_s(format_rfc2822(ts)) == s)?;
    let classic = must_ts(parse_http_date("Sun, 06 Nov 1994 08:49:37 GMT"));
    assert(must_s(format_http_date(classic)) == "Sun, 06 Nov 1994 08:49:37 GMT")?;
    let round = must_ts(parse_rfc2822(s));
    assert(round.nanos() == ts.nanos())?;
}

test("rfc2822 numeric zone") {
    let ts = must_ts(parse_rfc2822("Mon, 15 Jan 2024 12:30:00 -0500"));
    let utc = must_ts(parse_rfc3339("2024-01-15T17:30:00Z"));
    assert(ts.nanos() == utc.nanos())?;
}

test("rfc2822 garbage is ParseError") {
    expect_parse_error(parse_http_date("not-a-date"));
    expect_parse_error(parse_http_date("Tue, 01 Jan 2024 00:00:00 GMT"));
    expect_parse_error(parse_http_date("Mon, 01 Jan 2024 00:00:00 -0500"));
    expect_parse_error(parse_rfc2822("Mon, 32 Jan 2024 00:00:00 GMT"));
}
