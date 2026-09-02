// Userland time — FFI to native/libtime.{so,dylib,dll} (dload("time")).
// Instant handles live in the .so.
// Instant.drop removes the handle; missing/invalid is TimeError::InvalidInput.
//
// err_out is never a Coil array: pass coil_time_null() and read
// coil_time_last_error() after a failing call.

use string::{from_bytes, to_bytes};

extern "time" {
    fn coil_time_null() -> ptr;
    fn coil_time_last_error() -> int;
    fn coil_time_field(int i) -> int;
    fn coil_time_store_i64(int i, int v) -> int;
    fn coil_time_alloc(int n) -> ptr;
    fn coil_time_free(ptr p, int n);
    fn coil_time_store_u8(ptr p, int i, int v);
    fn coil_time_load_u8(ptr p, int i) -> int;

    fn coil_time_timestamp(ptr err_out) -> int;
    fn coil_time_sleep_ms(int millis, ptr err_out) -> int;
    fn coil_time_instant_now(ptr err_out) -> int;
    fn coil_time_instant_drop(int handle, ptr err_out) -> int;
    fn coil_time_elapsed_nanos(int handle, ptr err_out) -> int;
    fn coil_time_elapsed_millis(int handle, ptr err_out) -> int;
    fn coil_time_period(int years, int months, int days, int hours, int minutes, int secs, int millis, int micros, int nanos, ptr err_out) -> int;
    fn coil_time_period_hold() -> int;
    fn coil_time_add(int ts_nanos, ptr err_out) -> int;
    fn coil_time_sub(int ts_nanos, ptr err_out) -> int;
    fn coil_time_period_add(ptr err_out) -> int;
    fn coil_time_period_sub(ptr err_out) -> int;
    fn coil_time_date(ptr err_out) -> int;
    fn coil_time_date_from_period(ptr err_out) -> int;
    fn coil_time_date_from_epoch_period(ptr err_out) -> int;
    fn coil_time_epoch(ptr err_out) -> int;
    fn coil_time_format(int ts_nanos, ptr fmt, int fmt_len, ptr out, int out_len, ptr err_out) -> int;
    fn coil_time_parse(ptr text, int text_len, ptr fmt, int fmt_len, ptr err_out) -> int;
}

enum TimeError {
    InvalidInput,
    Overflow,
    ParseError,
    Other,
}

class Timestamp {
    secs: int,
    millis: int,
    micros: int,
    nanos: int,
}

class Period {
    years: int,
    months: int,
    days: int,
    hours: int,
    minutes: int,
    secs: int,
    millis: int,
    micros: int,
    nanos: int,
}

class Instant {
    handle: int,
    live: bool,
}

fn err_ptr() -> ptr {
    return coil_time_null();
}

fn err_from(int tag) -> TimeError {
    if tag == 0 {
        return TimeError::InvalidInput;
    }
    if tag == 1 {
        return TimeError::Overflow;
    }
    if tag == 2 {
        return TimeError::ParseError;
    }
    return TimeError::Other;
}

fn copy_in(Vec<byte> data) -> ptr {
    let n = len(data);
    let p = coil_time_alloc(n);
    for i in 0..n {
        let idx: int = i;
        let v: int = data[idx] as int;
        coil_time_store_u8(p, idx, v);
    }
    return p;
}

fn copy_out(ptr p, int n) -> Vec<byte> {
    let out: Vec<byte> = Vec::new();
    for i in 0..n {
        let idx: int = i;
        let v: int = coil_time_load_u8(p, idx);
        let b: byte = v as byte;
        out.push(b);
    }
    return out;
}

fn take_timestamp() -> Timestamp {
    let secs = coil_time_field(0);
    let millis = coil_time_field(1);
    let micros = coil_time_field(2);
    let nanos = coil_time_field(3);
    return new Timestamp(secs, millis, micros, nanos);
}

fn take_period() -> Period {
    let years = coil_time_field(0);
    let months = coil_time_field(1);
    let days = coil_time_field(2);
    let hours = coil_time_field(3);
    let minutes = coil_time_field(4);
    let secs = coil_time_field(5);
    let millis = coil_time_field(6);
    let micros = coil_time_field(7);
    let nanos = coil_time_field(8);
    return new Period(years, months, days, hours, minutes, secs, millis, micros, nanos);
}

fn put_period(Period p) {
    coil_time_store_i64(0, p.years());
    coil_time_store_i64(1, p.months());
    coil_time_store_i64(2, p.days());
    coil_time_store_i64(3, p.hours());
    coil_time_store_i64(4, p.minutes());
    coil_time_store_i64(5, p.secs());
    coil_time_store_i64(6, p.millis());
    coil_time_store_i64(7, p.micros());
    coil_time_store_i64(8, p.nanos());
}

fn timestamp() -> Result<Timestamp, TimeError> {
    let rc = coil_time_timestamp(err_ptr());
    if rc < 0 {
        raise err_from(coil_time_last_error());
    }
    return take_timestamp();
}

fn sleep_ms(int millis) -> Result<(), TimeError> {
    let rc = coil_time_sleep_ms(millis, err_ptr());
    if rc < 0 {
        raise err_from(coil_time_last_error());
    }
    return ();
}

fn instant_now() -> Instant {
    let id = coil_time_instant_now(err_ptr());
    return new Instant(id, true);
}

fn elapsed_nanos(Instant inst) -> Result<int, TimeError> {
    return match inst.elapsed_nanos() {
        Result::Ok(n) => n,
        Result::Err(e) => raise e,
    };
}

fn elapsed_millis(Instant inst) -> Result<int, TimeError> {
    return match inst.elapsed_millis() {
        Result::Ok(n) => n,
        Result::Err(e) => raise e,
    };
}

fn period(int years, int months, int days, int hours, int minutes, int secs, int millis, int micros, int nanos) -> Result<Period, TimeError> {
    let rc = coil_time_period(years, months, days, hours, minutes, secs, millis, micros, nanos, err_ptr());
    if rc < 0 {
        raise err_from(coil_time_last_error());
    }
    return take_period();
}

fn add(Timestamp ts, Period p) -> Result<Timestamp, TimeError> {
    put_period(p);
    let rc = coil_time_add(ts.nanos(), err_ptr());
    if rc < 0 {
        raise err_from(coil_time_last_error());
    }
    return take_timestamp();
}

fn sub(Timestamp ts, Period p) -> Result<Timestamp, TimeError> {
    put_period(p);
    let rc = coil_time_sub(ts.nanos(), err_ptr());
    if rc < 0 {
        raise err_from(coil_time_last_error());
    }
    return take_timestamp();
}

fn period_add(Period a, Period b) -> Result<Period, TimeError> {
    put_period(a);
    coil_time_period_hold();
    put_period(b);
    let rc = coil_time_period_add(err_ptr());
    if rc < 0 {
        raise err_from(coil_time_last_error());
    }
    return take_period();
}

fn period_sub(Period a, Period b) -> Result<Period, TimeError> {
    put_period(a);
    coil_time_period_hold();
    put_period(b);
    let rc = coil_time_period_sub(err_ptr());
    if rc < 0 {
        raise err_from(coil_time_last_error());
    }
    return take_period();
}

fn date() -> Result<Timestamp, TimeError> {
    let rc = coil_time_date(err_ptr());
    if rc < 0 {
        raise err_from(coil_time_last_error());
    }
    return take_timestamp();
}

fn date_from_period(Period p) -> Result<Timestamp, TimeError> {
    put_period(p);
    let rc = coil_time_date_from_period(err_ptr());
    if rc < 0 {
        raise err_from(coil_time_last_error());
    }
    return take_timestamp();
}

fn date_from_epoch_period(Period p) -> Result<Timestamp, TimeError> {
    put_period(p);
    let rc = coil_time_date_from_epoch_period(err_ptr());
    if rc < 0 {
        raise err_from(coil_time_last_error());
    }
    return take_timestamp();
}

fn epoch() -> Result<Timestamp, TimeError> {
    let rc = coil_time_epoch(err_ptr());
    if rc < 0 {
        raise err_from(coil_time_last_error());
    }
    return take_timestamp();
}

fn format(Timestamp ts, string fmt) -> Result<string, TimeError> {
    let fb = to_bytes(fmt);
    let fmt_n = len(fb);
    let src = copy_in(fb);
    let cap = 256;
    let out = coil_time_alloc(cap);
    let rc = coil_time_format(ts.nanos(), src, fmt_n, out, cap, err_ptr());
    let n = rc;
    if rc < 0 {
        n = 0;
    }
    let bytes = copy_out(out, n);
    coil_time_free(src, fmt_n);
    coil_time_free(out, cap);
    if rc < 0 {
        raise err_from(coil_time_last_error());
    }
    return match from_bytes(bytes) {
        Result::Ok(text) => text,
        Result::Err(_) => raise TimeError::Other,
    };
}

fn parse(string text, string fmt) -> Result<Timestamp, TimeError> {
    let tb = to_bytes(text);
    let tn = len(tb);
    let fb = to_bytes(fmt);
    let fmt_n = len(fb);
    let tp = copy_in(tb);
    let fp = copy_in(fb);
    let rc = coil_time_parse(tp, tn, fp, fmt_n, err_ptr());
    coil_time_free(tp, tn);
    coil_time_free(fp, fmt_n);
    if rc < 0 {
        raise err_from(coil_time_last_error());
    }
    return take_timestamp();
}

impl Timestamp {
    pub fn secs() -> int {
        return self.secs;
    }

    pub fn millis() -> int {
        return self.millis;
    }

    pub fn micros() -> int {
        return self.micros;
    }

    pub fn nanos() -> int {
        return self.nanos;
    }
}

impl Period {
    pub fn years() -> int {
        return self.years;
    }

    pub fn months() -> int {
        return self.months;
    }

    pub fn days() -> int {
        return self.days;
    }

    pub fn hours() -> int {
        return self.hours;
    }

    pub fn minutes() -> int {
        return self.minutes;
    }

    pub fn secs() -> int {
        return self.secs;
    }

    pub fn millis() -> int {
        return self.millis;
    }

    pub fn micros() -> int {
        return self.micros;
    }

    pub fn nanos() -> int {
        return self.nanos;
    }
}

impl Instant {
    pub fn elapsed_nanos() -> Result<int, TimeError> {
        let n = coil_time_elapsed_nanos(self.handle, err_ptr());
        if n < 0 {
            raise err_from(coil_time_last_error());
        }
        return n;
    }

    pub fn elapsed_millis() -> Result<int, TimeError> {
        let n = coil_time_elapsed_millis(self.handle, err_ptr());
        if n < 0 {
            raise err_from(coil_time_last_error());
        }
        return n;
    }

    pub fn is_live() -> bool {
        return self.live;
    }

    fn drop() {
        if self.live {
            coil_time_instant_drop(self.handle, coil_time_null());
            self.live = false;
        }
    }
}
