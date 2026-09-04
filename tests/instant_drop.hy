// Instant is a Coil mono snapshot. drop() clears live; elapsed then InvalidInput.
use time::{instant_now, elapsed_nanos, elapsed_millis, Instant, TimeError};
use gc::{collect};

fn expect_invalid(Result<int, TimeError> r) {
    match r {
        Result::Ok(_) => panic "expected InvalidInput",
        Result::Err(e) => match e {
            TimeError::InvalidInput => {},
            default => panic "wrong error",
        },
    };
}

test("instant elapsed after now is non-negative") {
    let inst = instant_now();
    let n = match elapsed_nanos(inst) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "elapsed_nanos",
    };
    assert(n >= 0)?;
    let ms = match elapsed_millis(inst) {
        Result::Ok(v) => v,
        Result::Err(_) => panic "elapsed_millis",
    };
    assert(ms >= 0)?;
}

test("drop then elapsed is InvalidInput") {
    let inst = instant_now();
    inst.drop();
    assert(inst.is_live() == false)?;
    expect_invalid(elapsed_nanos(inst));
    expect_invalid(elapsed_millis(inst));
}

test("drop is idempotent at Instant") {
    let inst = instant_now();
    inst.drop();
    inst.drop();
    assert(inst.is_live() == false)?;
    expect_invalid(elapsed_nanos(inst));
}

test("constructed dead Instant is InvalidInput") {
    let inst = new Instant(0, false);
    expect_invalid(elapsed_nanos(inst));
    inst.drop();
}

fn ephemeral_instant() {
    let _i = instant_now();
}

test("instant drop across collect") {
    ephemeral_instant();
    collect();
    assert(true)?;
}

test("explicit drop then collect") {
    let inst = instant_now();
    inst.drop();
    collect();
    assert(inst.is_live() == false)?;
    expect_invalid(elapsed_nanos(inst));
}
