// Pins: sixteen TIME_WIRING names at package arity. Instant.drop is extra.
use time::{timestamp, sleep_ms, instant_now, elapsed_nanos, elapsed_millis, period, add, sub, period_add, period_sub, date, date_from_period, date_from_epoch_period, epoch, format, parse, Instant, TimeError, Timestamp, Period};

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

fn pin_time_error(TimeError e) -> int {
    return match e {
        TimeError::InvalidInput => 0,
        TimeError::Overflow => 1,
        TimeError::ParseError => 2,
        TimeError::Other => 3,
    };
}

test("sixteen names at TIME_WIRING arity") {
    let _ts = must_ts(timestamp());
    match sleep_ms(0) {
        Result::Ok(_) => {},
        Result::Err(_) => panic "sleep_ms",
    };
    let inst: Instant = instant_now();
    match elapsed_nanos(inst) {
        Result::Ok(n) => assert(n >= 0)?,
        Result::Err(_) => panic "elapsed_nanos",
    };
    match elapsed_millis(inst) {
        Result::Ok(n) => assert(n >= 0)?,
        Result::Err(_) => panic "elapsed_millis",
    };
    inst.drop();
    let p = must_p(period(0, 0, 1, 0, 0, 0, 0, 0, 0));
    assert(p.years() == 0)?;
    assert(p.months() == 0)?;
    assert(p.days() == 1)?;
    assert(p.hours() == 0)?;
    assert(p.minutes() == 0)?;
    assert(p.secs() == 0)?;
    assert(p.millis() == 0)?;
    assert(p.micros() == 0)?;
    assert(p.nanos() == 0)?;
    let e = must_ts(epoch());
    assert(e.secs() == 0)?;
    assert(e.millis() == 0)?;
    assert(e.micros() == 0)?;
    assert(e.nanos() == 0)?;
    let day = must_p(period(0, 0, 1, 0, 0, 0, 0, 0, 0));
    let plus = must_ts(add(e, day));
    assert(plus.secs() == 86400)?;
    let back = must_ts(sub(plus, day));
    assert(back.nanos() == 0)?;
    let summed = must_p(period_add(p, day));
    assert(summed.days() == 2)?;
    let diff = must_p(period_sub(summed, day));
    assert(diff.days() == 1)?;
    let _d = must_ts(date());
    let cal = must_p(period(2024, 1, 1, 0, 0, 0, 0, 0, 0));
    let _from_p = must_ts(date_from_period(cal));
    let from_epoch = must_ts(date_from_epoch_period(day));
    assert(from_epoch.secs() == 86400)?;
    assert(from_epoch.nanos() == 86400 * 1000000000)?;
    let parsed = must_ts(parse("2024-01-01 00:00:00", "%Y-%m-%d %H:%M:%S"));
    let s = match format(parsed, "%Y-%m-%d %H:%M:%S") {
        Result::Ok(t) => t,
        Result::Err(_) => panic "format",
    };
    assert(s == "2024-01-01 00:00:00")?;
}

test("TimeError tags match virtual wire") {
    assert(pin_time_error(TimeError::InvalidInput) == 0)?;
    assert(pin_time_error(TimeError::Overflow) == 1)?;
    assert(pin_time_error(TimeError::ParseError) == 2)?;
    assert(pin_time_error(TimeError::Other) == 3)?;
}

test("date_from_epoch_period is epoch plus period") {
    let p = must_p(period(0, 0, 1, 0, 0, 0, 0, 0, 0));
    let ts = must_ts(date_from_epoch_period(p));
    assert(ts.secs() == 86400)?;
    assert(ts.nanos() == 86400 * 1000000000)?;
}
