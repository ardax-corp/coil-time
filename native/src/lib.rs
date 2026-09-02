//! C ABI for coil-time (`coil_time_*`).
//!
//! Port of coil-lang `machine/src/time.rs` (16 ops) plus Instant `drop`.
//! Instants are opaque `int` handles into a process-global HashMap.

use chrono::{DateTime, Months, NaiveDate, NaiveDateTime, TimeDelta, Utc};
use std::cell::Cell;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{LazyLock, Mutex};
use std::thread;
use std::time::{Duration, Instant as StdInstant};

#[derive(Clone, Copy)]
struct FormatHold {
    fmt: *const u8,
    fmt_len: u64,
    out: *mut u8,
    out_len: u64,
}

thread_local! {
    static LAST_ERROR: Cell<i64> = const { Cell::new(0) };
    static LAST_I64: Cell<i64> = const { Cell::new(0) };
    static FIELDS: Cell<[i64; 9]> = const { Cell::new([0; 9]) };
    static FORMAT_HOLD: Cell<FormatHold> = const {
        Cell::new(FormatHold {
            fmt: std::ptr::null(),
            fmt_len: 0,
            out: std::ptr::null_mut(),
            out_len: 0,
        })
    };
}

/// Error tags (same order as userland `TimeError` / virtual `TimeErrorTag`).
#[repr(i64)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum TimeErrorTag {
    InvalidInput = 0,
    Overflow = 1,
    ParseError = 2,
    Other = 3,
}

const NS_PER_SEC: i64 = 1_000_000_000;
const NS_PER_MS: i64 = 1_000_000;
const NS_PER_US: i64 = 1_000;
const RC_ERR: i64 = -1;
const RC_OK: i64 = 0;

static NEXT_INSTANT_ID: AtomicU64 = AtomicU64::new(1);
static INSTANTS: LazyLock<Mutex<HashMap<u64, StdInstant>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct PeriodParts {
    years: i64,
    months: i64,
    days: i64,
    hours: i64,
    minutes: i64,
    secs: i64,
    millis: i64,
    micros: i64,
    nanos: i64,
}

unsafe fn write_err(err_out: *mut i64, tag: TimeErrorTag) {
    LAST_ERROR.with(|c| c.set(tag as i64));
    if !err_out.is_null() {
        unsafe {
            *err_out = tag as i64;
        }
    }
}

unsafe fn fail(err_out: *mut i64, tag: TimeErrorTag) -> i64 {
    unsafe { write_err(err_out, tag) };
    RC_ERR
}

unsafe fn in_slice<'a>(ptr: *const u8, len: u64) -> Result<&'a [u8], TimeErrorTag> {
    if len == 0 {
        return Ok(&[]);
    }
    if ptr.is_null() {
        return Err(TimeErrorTag::InvalidInput);
    }
    let n = usize::try_from(len).map_err(|_| TimeErrorTag::InvalidInput)?;
    Ok(unsafe { std::slice::from_raw_parts(ptr, n) })
}

unsafe fn out_slice<'a>(ptr: *mut u8, len: u64) -> Result<&'a mut [u8], TimeErrorTag> {
    if len == 0 {
        return Ok(&mut []);
    }
    if ptr.is_null() {
        return Err(TimeErrorTag::InvalidInput);
    }
    let n = usize::try_from(len).map_err(|_| TimeErrorTag::InvalidInput)?;
    Ok(unsafe { std::slice::from_raw_parts_mut(ptr, n) })
}

fn set_fields(vals: [i64; 9]) {
    FIELDS.with(|c| c.set(vals));
}

fn get_fields() -> [i64; 9] {
    FIELDS.with(|c| c.get())
}

fn nanos_to_scales(nanos: i64) -> (i64, i64, i64, i64) {
    let secs = nanos.div_euclid(NS_PER_SEC);
    let millis = nanos.div_euclid(NS_PER_MS);
    let micros = nanos.div_euclid(NS_PER_US);
    (secs, millis, micros, nanos)
}

fn set_timestamp_fields(nanos: i64) {
    let (secs, millis, micros, nanos) = nanos_to_scales(nanos);
    LAST_I64.with(|c| c.set(nanos));
    set_fields([secs, millis, micros, nanos, 0, 0, 0, 0, 0]);
}

fn set_period_fields(p: PeriodParts) {
    set_fields([
        p.years, p.months, p.days, p.hours, p.minutes, p.secs, p.millis, p.micros, p.nanos,
    ]);
}

fn period_from_fields() -> PeriodParts {
    let f = get_fields();
    PeriodParts {
        years: f[0],
        months: f[1],
        days: f[2],
        hours: f[3],
        minutes: f[4],
        secs: f[5],
        millis: f[6],
        micros: f[7],
        nanos: f[8],
    }
}

fn nanos_to_utc(nanos: i64) -> Result<DateTime<Utc>, TimeErrorTag> {
    let secs = nanos.div_euclid(NS_PER_SEC);
    let sub = nanos.rem_euclid(NS_PER_SEC);
    if sub > i32::MAX as i64 {
        return Err(TimeErrorTag::Overflow);
    }
    DateTime::from_timestamp(secs, sub as u32).ok_or(TimeErrorTag::Overflow)
}

fn utc_to_nanos(dt: DateTime<Utc>) -> Result<i64, TimeErrorTag> {
    let secs = dt.timestamp();
    let nsec = i64::from(dt.timestamp_subsec_nanos());
    secs.checked_mul(NS_PER_SEC)
        .and_then(|s| s.checked_add(nsec))
        .ok_or(TimeErrorTag::Overflow)
}

fn period_to_timedelta(p: &PeriodParts) -> Result<TimeDelta, TimeErrorTag> {
    let mut delta = TimeDelta::zero();
    let add = |delta: TimeDelta,
               n: i64,
               f: fn(i64) -> Option<TimeDelta>|
     -> Result<TimeDelta, TimeErrorTag> {
        if n == 0 {
            return Ok(delta);
        }
        let piece = f(n).ok_or(TimeErrorTag::Overflow)?;
        delta.checked_add(&piece).ok_or(TimeErrorTag::Overflow)
    };
    delta = add(delta, p.days, TimeDelta::try_days)?;
    delta = add(delta, p.hours, TimeDelta::try_hours)?;
    delta = add(delta, p.minutes, TimeDelta::try_minutes)?;
    delta = add(delta, p.secs, TimeDelta::try_seconds)?;
    delta = add(delta, p.millis, TimeDelta::try_milliseconds)?;
    delta = add(delta, p.micros, |n| Some(TimeDelta::microseconds(n)))?;
    delta = add(delta, p.nanos, |n| Some(TimeDelta::nanoseconds(n)))?;
    Ok(delta)
}

fn add_months(date: NaiveDate, months: i32) -> Result<NaiveDate, TimeErrorTag> {
    if months == 0 {
        return Ok(date);
    }
    if months > 0 {
        date.checked_add_months(Months::new(months as u32))
            .ok_or(TimeErrorTag::Overflow)
    } else {
        date.checked_sub_months(Months::new((-months) as u32))
            .ok_or(TimeErrorTag::Overflow)
    }
}

fn apply_period_to_nanos(nanos: i64, p: &PeriodParts) -> Result<i64, TimeErrorTag> {
    let mut dt = nanos_to_utc(nanos)?;
    let month_delta = p
        .years
        .checked_mul(12)
        .and_then(|y| y.checked_add(p.months))
        .ok_or(TimeErrorTag::Overflow)?;
    if month_delta != 0 {
        let date = add_months(dt.date_naive(), month_delta as i32)?;
        let naive = NaiveDateTime::new(date, dt.time());
        dt = DateTime::from_naive_utc_and_offset(naive, Utc);
    }
    let delta = period_to_timedelta(p)?;
    if delta != TimeDelta::zero() {
        dt = dt.checked_add_signed(delta).ok_or(TimeErrorTag::Overflow)?;
    }
    utc_to_nanos(dt)
}

fn period_add_parts(a: PeriodParts, b: PeriodParts) -> Result<PeriodParts, TimeErrorTag> {
    let sum = |x: i64, y: i64| x.checked_add(y).ok_or(TimeErrorTag::Overflow);
    Ok(PeriodParts {
        years: sum(a.years, b.years)?,
        months: sum(a.months, b.months)?,
        days: sum(a.days, b.days)?,
        hours: sum(a.hours, b.hours)?,
        minutes: sum(a.minutes, b.minutes)?,
        secs: sum(a.secs, b.secs)?,
        millis: sum(a.millis, b.millis)?,
        micros: sum(a.micros, b.micros)?,
        nanos: sum(a.nanos, b.nanos)?,
    })
}

fn period_sub_parts(a: PeriodParts, b: PeriodParts) -> Result<PeriodParts, TimeErrorTag> {
    let sub = |x: i64, y: i64| x.checked_sub(y).ok_or(TimeErrorTag::Overflow);
    Ok(PeriodParts {
        years: sub(a.years, b.years)?,
        months: sub(a.months, b.months)?,
        days: sub(a.days, b.days)?,
        hours: sub(a.hours, b.hours)?,
        minutes: sub(a.minutes, b.minutes)?,
        secs: sub(a.secs, b.secs)?,
        millis: sub(a.millis, b.millis)?,
        micros: sub(a.micros, b.micros)?,
        nanos: sub(a.nanos, b.nanos)?,
    })
}

fn register_instant(start: StdInstant) -> u64 {
    let id = NEXT_INSTANT_ID.fetch_add(1, Ordering::Relaxed);
    INSTANTS.lock().expect("instant registry").insert(id, start);
    id
}

fn instant_from_id(id: i64) -> Result<StdInstant, TimeErrorTag> {
    if id <= 0 {
        return Err(TimeErrorTag::InvalidInput);
    }
    INSTANTS
        .lock()
        .expect("instant registry")
        .get(&(id as u64))
        .copied()
        .ok_or(TimeErrorTag::InvalidInput)
}

fn drop_instant(id: i64) -> Result<(), TimeErrorTag> {
    if id <= 0 {
        return Err(TimeErrorTag::InvalidInput);
    }
    INSTANTS
        .lock()
        .expect("instant registry")
        .remove(&(id as u64))
        .map(|_| ())
        .ok_or(TimeErrorTag::InvalidInput)
}

fn negate_period(p: PeriodParts) -> Result<PeriodParts, TimeErrorTag> {
    let neg = |n: i64| n.checked_neg().ok_or(TimeErrorTag::Overflow);
    Ok(PeriodParts {
        years: neg(p.years)?,
        months: neg(p.months)?,
        days: neg(p.days)?,
        hours: neg(p.hours)?,
        minutes: neg(p.minutes)?,
        secs: neg(p.secs)?,
        millis: neg(p.millis)?,
        micros: neg(p.micros)?,
        nanos: neg(p.nanos)?,
    })
}

/// Packed-buffer helper for Coil FFI marshalling (not a TIME_WIRING name).
#[no_mangle]
pub extern "C" fn coil_time_null() -> *mut u8 {
    std::ptr::null_mut()
}

#[no_mangle]
pub extern "C" fn coil_time_last_error() -> i64 {
    LAST_ERROR.with(|c| c.get())
}

#[no_mangle]
pub extern "C" fn coil_time_last_i64() -> i64 {
    LAST_I64.with(|c| c.get())
}

#[no_mangle]
pub extern "C" fn coil_time_field(i: i64) -> i64 {
    let f = get_fields();
    match usize::try_from(i) {
        Ok(idx) if idx < 9 => f[idx],
        _ => 0,
    }
}

#[no_mangle]
pub extern "C" fn coil_time_store_i64(i: i64, v: i64) -> i64 {
    let Ok(idx) = usize::try_from(i) else {
        return RC_ERR;
    };
    if idx >= 9 {
        return RC_ERR;
    }
    let mut f = get_fields();
    f[idx] = v;
    set_fields(f);
    RC_OK
}

#[no_mangle]
pub unsafe extern "C" fn coil_time_alloc(n: u64) -> *mut u8 {
    if n == 0 {
        return std::ptr::null_mut();
    }
    let Ok(len) = usize::try_from(n) else {
        return std::ptr::null_mut();
    };
    let mut v = vec![0_u8; len];
    let ptr = v.as_mut_ptr();
    std::mem::forget(v);
    ptr
}

#[no_mangle]
pub unsafe extern "C" fn coil_time_free(ptr: *mut u8, n: u64) {
    if ptr.is_null() || n == 0 {
        return;
    }
    let Ok(len) = usize::try_from(n) else {
        return;
    };
    drop(unsafe { Vec::from_raw_parts(ptr, len, len) });
}

#[no_mangle]
pub unsafe extern "C" fn coil_time_store_u8(ptr: *mut u8, i: u64, v: i64) {
    if ptr.is_null() {
        return;
    }
    let Ok(idx) = usize::try_from(i) else {
        return;
    };
    unsafe {
        *ptr.add(idx) = v as u8;
    }
}

#[no_mangle]
pub unsafe extern "C" fn coil_time_load_u8(ptr: *const u8, i: u64) -> i64 {
    if ptr.is_null() {
        return 0;
    }
    let Ok(idx) = usize::try_from(i) else {
        return 0;
    };
    unsafe { *ptr.add(idx) as i64 }
}

#[no_mangle]
pub unsafe extern "C" fn coil_time_timestamp(err_out: *mut i64) -> i64 {
    let nanos = Utc::now().timestamp_nanos_opt().unwrap_or(0);
    set_timestamp_fields(nanos);
    LAST_ERROR.with(|c| c.set(0));
    let _ = err_out;
    RC_OK
}

#[no_mangle]
pub unsafe extern "C" fn coil_time_sleep_ms(millis: i64, err_out: *mut i64) -> i64 {
    if millis < 0 {
        return unsafe { fail(err_out, TimeErrorTag::InvalidInput) };
    }
    thread::sleep(Duration::from_millis(millis as u64));
    LAST_ERROR.with(|c| c.set(0));
    RC_OK
}

#[no_mangle]
pub unsafe extern "C" fn coil_time_instant_now(err_out: *mut i64) -> i64 {
    let id = register_instant(StdInstant::now());
    LAST_ERROR.with(|c| c.set(0));
    LAST_I64.with(|c| c.set(id as i64));
    let _ = err_out;
    id as i64
}

#[no_mangle]
pub unsafe extern "C" fn coil_time_instant_drop(handle: i64, err_out: *mut i64) -> i64 {
    match drop_instant(handle) {
        Ok(()) => {
            LAST_ERROR.with(|c| c.set(0));
            RC_OK
        }
        Err(tag) => unsafe { fail(err_out, tag) },
    }
}

#[no_mangle]
pub unsafe extern "C" fn coil_time_elapsed_nanos(handle: i64, err_out: *mut i64) -> i64 {
    let start = match instant_from_id(handle) {
        Ok(s) => s,
        Err(tag) => return unsafe { fail(err_out, tag) },
    };
    let n = i64::try_from(start.elapsed().as_nanos()).unwrap_or(i64::MAX);
    LAST_I64.with(|c| c.set(n));
    LAST_ERROR.with(|c| c.set(0));
    n
}

#[no_mangle]
pub unsafe extern "C" fn coil_time_elapsed_millis(handle: i64, err_out: *mut i64) -> i64 {
    let start = match instant_from_id(handle) {
        Ok(s) => s,
        Err(tag) => return unsafe { fail(err_out, tag) },
    };
    let n = i64::try_from(start.elapsed().as_millis()).unwrap_or(i64::MAX);
    LAST_I64.with(|c| c.set(n));
    LAST_ERROR.with(|c| c.set(0));
    n
}

#[no_mangle]
pub unsafe extern "C" fn coil_time_period(
    years: i64,
    months: i64,
    days: i64,
    hours: i64,
    minutes: i64,
    secs: i64,
    millis: i64,
    micros: i64,
    nanos: i64,
    err_out: *mut i64,
) -> i64 {
    set_period_fields(PeriodParts {
        years,
        months,
        days,
        hours,
        minutes,
        secs,
        millis,
        micros,
        nanos,
    });
    LAST_ERROR.with(|c| c.set(0));
    let _ = err_out;
    RC_OK
}

#[no_mangle]
pub unsafe extern "C" fn coil_time_add(ts_nanos: i64, err_out: *mut i64) -> i64 {
    let p = period_from_fields();
    match apply_period_to_nanos(ts_nanos, &p) {
        Ok(out) => {
            set_timestamp_fields(out);
            LAST_ERROR.with(|c| c.set(0));
            RC_OK
        }
        Err(tag) => unsafe { fail(err_out, tag) },
    }
}

#[no_mangle]
pub unsafe extern "C" fn coil_time_sub(ts_nanos: i64, err_out: *mut i64) -> i64 {
    let p = period_from_fields();
    let neg = match negate_period(p) {
        Ok(n) => n,
        Err(tag) => return unsafe { fail(err_out, tag) },
    };
    match apply_period_to_nanos(ts_nanos, &neg) {
        Ok(out) => {
            set_timestamp_fields(out);
            LAST_ERROR.with(|c| c.set(0));
            RC_OK
        }
        Err(tag) => unsafe { fail(err_out, tag) },
    }
}

thread_local! {
    static ACCUM: Cell<PeriodParts> = const { Cell::new(PeriodParts {
        years: 0,
        months: 0,
        days: 0,
        hours: 0,
        minutes: 0,
        secs: 0,
        millis: 0,
        micros: 0,
        nanos: 0,
    }) };
}

#[no_mangle]
pub extern "C" fn coil_time_period_hold() -> i64 {
    ACCUM.with(|c| c.set(period_from_fields()));
    RC_OK
}

#[no_mangle]
pub unsafe extern "C" fn coil_time_period_add(err_out: *mut i64) -> i64 {
    unsafe { coil_time_period_fold(1, err_out) }
}

#[no_mangle]
pub unsafe extern "C" fn coil_time_period_sub(err_out: *mut i64) -> i64 {
    unsafe { coil_time_period_fold(-1, err_out) }
}

unsafe fn coil_time_period_fold(sign: i64, err_out: *mut i64) -> i64 {
    let a = ACCUM.with(|c| c.get());
    let b = period_from_fields();
    let r = if sign >= 0 {
        period_add_parts(a, b)
    } else {
        period_sub_parts(a, b)
    };
    match r {
        Ok(p) => {
            set_period_fields(p);
            LAST_ERROR.with(|c| c.set(0));
            RC_OK
        }
        Err(tag) => unsafe { fail(err_out, tag) },
    }
}

#[no_mangle]
pub unsafe extern "C" fn coil_time_date(err_out: *mut i64) -> i64 {
    let today = Utc::now().date_naive();
    let naive = today.and_hms_opt(0, 0, 0).expect("midnight");
    let dt = DateTime::<Utc>::from_naive_utc_and_offset(naive, Utc);
    match utc_to_nanos(dt) {
        Ok(nanos) => {
            set_timestamp_fields(nanos);
            LAST_ERROR.with(|c| c.set(0));
            RC_OK
        }
        Err(tag) => unsafe { fail(err_out, tag) },
    }
}

#[no_mangle]
pub unsafe extern "C" fn coil_time_date_from_period(err_out: *mut i64) -> i64 {
    let period = period_from_fields();
    let r = (|| {
        let y = i32::try_from(period.years).map_err(|_| TimeErrorTag::Overflow)?;
        let m = u32::try_from(period.months).map_err(|_| TimeErrorTag::Overflow)?;
        let d = u32::try_from(period.days).map_err(|_| TimeErrorTag::Overflow)?;
        if m == 0 || d == 0 {
            return Err(TimeErrorTag::InvalidInput);
        }
        let date = NaiveDate::from_ymd_opt(y, m, d).ok_or(TimeErrorTag::InvalidInput)?;
        let naive = date
            .and_hms_opt(0, 0, 0)
            .ok_or(TimeErrorTag::InvalidInput)?;
        let dt = DateTime::<Utc>::from_naive_utc_and_offset(naive, Utc);
        utc_to_nanos(dt)
    })();
    match r {
        Ok(nanos) => {
            set_timestamp_fields(nanos);
            LAST_ERROR.with(|c| c.set(0));
            RC_OK
        }
        Err(tag) => unsafe { fail(err_out, tag) },
    }
}

#[no_mangle]
pub unsafe extern "C" fn coil_time_date_from_epoch_period(err_out: *mut i64) -> i64 {
    let period = period_from_fields();
    match apply_period_to_nanos(0, &period) {
        Ok(out) => {
            set_timestamp_fields(out);
            LAST_ERROR.with(|c| c.set(0));
            RC_OK
        }
        Err(tag) => unsafe { fail(err_out, tag) },
    }
}

#[no_mangle]
pub unsafe extern "C" fn coil_time_epoch(err_out: *mut i64) -> i64 {
    set_timestamp_fields(0);
    LAST_ERROR.with(|c| c.set(0));
    let _ = err_out;
    RC_OK
}

/// Coil FFI arity stays small: hold buffers, then apply. Native tests still use the 6-arg form.
#[no_mangle]
pub unsafe extern "C" fn coil_time_format_hold(
    fmt: *const u8,
    fmt_len: u64,
    out: *mut u8,
    out_len: u64,
) -> i64 {
    FORMAT_HOLD.with(|c| {
        c.set(FormatHold {
            fmt,
            fmt_len,
            out,
            out_len,
        });
    });
    RC_OK
}

#[no_mangle]
pub unsafe extern "C" fn coil_time_format_apply(ts_nanos: i64, err_out: *mut i64) -> i64 {
    let h = FORMAT_HOLD.with(|c| c.get());
    unsafe { coil_time_format(ts_nanos, h.fmt, h.fmt_len, h.out, h.out_len, err_out) }
}

#[no_mangle]
pub unsafe extern "C" fn coil_time_format(
    ts_nanos: i64,
    fmt: *const u8,
    fmt_len: u64,
    out: *mut u8,
    out_len: u64,
    err_out: *mut i64,
) -> i64 {
    let nanos = ts_nanos;
    let fmt_bytes = match unsafe { in_slice(fmt, fmt_len) } {
        Ok(b) => b,
        Err(tag) => return unsafe { fail(err_out, tag) },
    };
    let fmt_str = match std::str::from_utf8(fmt_bytes) {
        Ok(s) => s,
        Err(_) => return unsafe { fail(err_out, TimeErrorTag::InvalidInput) },
    };
    let dt = match nanos_to_utc(nanos) {
        Ok(d) => d,
        Err(tag) => return unsafe { fail(err_out, tag) },
    };
    let s = dt.format(fmt_str).to_string();
    let dst = match unsafe { out_slice(out, out_len) } {
        Ok(b) => b,
        Err(tag) => return unsafe { fail(err_out, tag) },
    };
    if dst.len() < s.len() {
        return unsafe { fail(err_out, TimeErrorTag::Overflow) };
    }
    dst[..s.len()].copy_from_slice(s.as_bytes());
    LAST_ERROR.with(|c| c.set(0));
    i64::try_from(s.len()).unwrap_or(RC_ERR)
}

#[no_mangle]
pub unsafe extern "C" fn coil_time_parse(
    text: *const u8,
    text_len: u64,
    fmt: *const u8,
    fmt_len: u64,
    err_out: *mut i64,
) -> i64 {
    let input_bytes = match unsafe { in_slice(text, text_len) } {
        Ok(b) => b,
        Err(tag) => return unsafe { fail(err_out, tag) },
    };
    let fmt_bytes = match unsafe { in_slice(fmt, fmt_len) } {
        Ok(b) => b,
        Err(tag) => return unsafe { fail(err_out, tag) },
    };
    let input = match std::str::from_utf8(input_bytes) {
        Ok(s) => s,
        Err(_) => return unsafe { fail(err_out, TimeErrorTag::InvalidInput) },
    };
    let fmt_str = match std::str::from_utf8(fmt_bytes) {
        Ok(s) => s,
        Err(_) => return unsafe { fail(err_out, TimeErrorTag::InvalidInput) },
    };
    let naive = match NaiveDateTime::parse_from_str(input, fmt_str) {
        Ok(n) => n,
        Err(_) => return unsafe { fail(err_out, TimeErrorTag::ParseError) },
    };
    let dt = DateTime::<Utc>::from_naive_utc_and_offset(naive, Utc);
    match utc_to_nanos(dt) {
        Ok(nanos) => {
            set_timestamp_fields(nanos);
            LAST_ERROR.with(|c| c.set(0));
            RC_OK
        }
        Err(tag) => unsafe { fail(err_out, tag) },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn err_ptr() -> *mut i64 {
        std::ptr::null_mut()
    }

    #[test]
    fn format_parse_roundtrip() {
        let nanos = 1_704_067_200_i64 * NS_PER_SEC;
        set_timestamp_fields(nanos);
        LAST_I64.with(|c| c.set(nanos));
        let fmt = b"%Y-%m-%d %H:%M:%S";
        let mut out = [0_u8; 64];
        let n = unsafe {
            coil_time_format(
                nanos,
                fmt.as_ptr(),
                fmt.len() as u64,
                out.as_mut_ptr(),
                out.len() as u64,
                err_ptr(),
            )
        };
        assert!(n > 0, "format failed tag={}", coil_time_last_error());
        let s = std::str::from_utf8(&out[..n as usize]).unwrap();
        assert_eq!(s, "2024-01-01 00:00:00");
        let rc = unsafe {
            coil_time_parse(
                out.as_ptr(),
                n as u64,
                fmt.as_ptr(),
                fmt.len() as u64,
                err_ptr(),
            )
        };
        assert_eq!(rc, RC_OK);
        assert_eq!(coil_time_field(3), nanos);
    }

    #[test]
    fn period_add_fields() {
        unsafe {
            coil_time_period(0, 0, 1, 2, 0, 0, 0, 0, 0, err_ptr());
            coil_time_period_hold();
            coil_time_period(0, 0, 3, 0, 5, 0, 0, 0, 0, err_ptr());
            let rc = coil_time_period_add(err_ptr());
            assert_eq!(rc, RC_OK);
        }
        assert_eq!(coil_time_field(2), 4);
        assert_eq!(coil_time_field(3), 2);
        assert_eq!(coil_time_field(4), 5);
    }

    #[test]
    fn period_add_overflow_is_overflow_tag() {
        unsafe {
            coil_time_period(i64::MAX, 0, 0, 0, 0, 0, 0, 0, 0, err_ptr());
            coil_time_period_hold();
            coil_time_period(1, 0, 0, 0, 0, 0, 0, 0, 0, err_ptr());
            let rc = coil_time_period_add(err_ptr());
            assert_eq!(rc, RC_ERR);
            assert_eq!(coil_time_last_error(), TimeErrorTag::Overflow as i64);
        }
    }

    #[test]
    fn date_from_period_rejects_zero_month_and_instant_invalid() {
        unsafe {
            coil_time_period(2024, 0, 1, 0, 0, 0, 0, 0, 0, err_ptr());
            let r = coil_time_date_from_period(err_ptr());
            assert_eq!(r, RC_ERR);
            assert_eq!(coil_time_last_error(), TimeErrorTag::InvalidInput as i64);

            let elapsed = coil_time_elapsed_nanos(0, err_ptr());
            assert_eq!(elapsed, RC_ERR);
            assert_eq!(coil_time_last_error(), TimeErrorTag::InvalidInput as i64);
        }
    }

    #[test]
    fn timestamp_add_one_month_from_known_epoch() {
        let nanos = 1_704_067_200_i64 * NS_PER_SEC;
        unsafe {
            coil_time_period(0, 1, 0, 0, 0, 0, 0, 0, 0, err_ptr());
            let rc = coil_time_add(nanos, err_ptr());
            assert_eq!(rc, RC_OK);
        }
        assert_eq!(coil_time_field(3), 1_706_745_600_i64 * NS_PER_SEC);
    }

    #[test]
    fn instant_drop_removes_handle() {
        let id = unsafe { coil_time_instant_now(err_ptr()) };
        assert!(id > 0);
        let n = unsafe { coil_time_elapsed_nanos(id, err_ptr()) };
        assert!(n >= 0, "elapsed before drop tag={}", coil_time_last_error());
        let rc = unsafe { coil_time_instant_drop(id, err_ptr()) };
        assert_eq!(rc, RC_OK);
        let after = unsafe { coil_time_elapsed_nanos(id, err_ptr()) };
        assert_eq!(after, RC_ERR);
        assert_eq!(coil_time_last_error(), TimeErrorTag::InvalidInput as i64);
        let again = unsafe { coil_time_instant_drop(id, err_ptr()) };
        assert_eq!(again, RC_ERR);
        assert_eq!(coil_time_last_error(), TimeErrorTag::InvalidInput as i64);
    }

    #[test]
    fn instant_drop_rejects_invalid_handles() {
        for id in [0_i64, -1, 1_000_000_009] {
            let rc = unsafe { coil_time_instant_drop(id, err_ptr()) };
            assert_eq!(rc, RC_ERR, "id={id}");
            assert_eq!(coil_time_last_error(), TimeErrorTag::InvalidInput as i64);
        }
    }

    #[test]
    fn epoch_is_zero_nanos() {
        unsafe {
            let rc = coil_time_epoch(err_ptr());
            assert_eq!(rc, RC_OK);
        }
        assert_eq!(coil_time_field(0), 0);
        assert_eq!(coil_time_field(3), 0);
    }
}
