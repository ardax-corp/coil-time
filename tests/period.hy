// Period field add/sub and overflow (virtual period_add_parts).
use time::{period, period_add, period_sub, date_from_period, TimeError, Period};

fn must_p(Result<Period, TimeError> r) -> Period {
    return match r {
        Result::Ok(p) => p,
        Result::Err(_) => panic "period",
    };
}

test("period add fields") {
    let a = must_p(period(0, 0, 1, 2, 0, 0, 0, 0, 0));
    let b = must_p(period(0, 0, 3, 0, 5, 0, 0, 0, 0));
    let p = must_p(period_add(a, b));
    assert(p.days() == 4)?;
    assert(p.hours() == 2)?;
    assert(p.minutes() == 5)?;
}

test("period sub fields") {
    let a = must_p(period(0, 0, 4, 2, 5, 0, 0, 0, 0));
    let b = must_p(period(0, 0, 1, 2, 0, 0, 0, 0, 0));
    let p = must_p(period_sub(a, b));
    assert(p.days() == 3)?;
    assert(p.hours() == 0)?;
    assert(p.minutes() == 5)?;
}

test("period add overflow is Overflow") {
    let half = 2 ** 62;
    let a = must_p(period(half, 0, 0, 0, 0, 0, 0, 0, 0));
    let b = must_p(period(half, 0, 0, 0, 0, 0, 0, 0, 0));
    match period_add(a, b) {
        Result::Ok(_) => panic "expected Overflow",
        Result::Err(e) => match e {
            TimeError::Overflow => {},
            default => panic "wrong error",
        },
    };
}

test("date_from_period year overflow") {
    let huge = must_p(period(3000000000, 1, 1, 0, 0, 0, 0, 0, 0));
    match date_from_period(huge) {
        Result::Ok(_) => panic "expected Overflow",
        Result::Err(e) => match e {
            TimeError::Overflow => {},
            default => panic "wrong error",
        },
    };
}
