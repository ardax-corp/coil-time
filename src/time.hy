// Wall-clock and monotonic time, UTC calendar math, and date formatting.
//
// `Timestamp` is a point in time since the Unix epoch (`timestamp`, `date`,
// `epoch`); `Period` is a calendar-aware amount of time for `add` / `sub`;
// `Instant` measures elapsed time on the monotonic clock (`instant_now`).
// `format` / `parse` take `%Y-%m-%d`-style patterns, and the named helpers
// read and write RFC 3339, ISO 8601, RFC 2822 and HTTP dates. Everything is
// UTC; there are no time zones.
//
// Process clocks are the compiler's virtual `clock` module (`wall_nanos` /
// `mono_nanos` / `sleep_ms`); the calendar math is plain Coil in this file.

use clock::{wall_nanos, mono_nanos, sleep_ms as host_sleep_ms};
use string::{format as sfmt, to_bytes, from_bytes};

const NS_PER_SEC = 1000000000;
const NS_PER_MS = 1000000;
const NS_PER_US = 1000;
const NS_PER_MIN = 60000000000;
const NS_PER_HOUR = 3600000000000;
const NS_PER_DAY = 86400000000000;
fn i64_max() -> int {
    let p = 2 ** 62;
    return (p - 1) * 2 + 1;
}

fn i64_min() -> int {
    return 0 - i64_max() - 1;
}
const I32_MAX = 2147483647;
const I32_MIN = -2147483648;

// Pattern for `format` / `parse` (calendar date only; no zone).
/// `format` / `parse` pattern for a calendar date, `YYYY-MM-DD` (no time, no zone).
///
/// # Examples
///
/// ```
/// use time::{parse, format, ISO8601_DATE};
/// # use tests::assert;
/// let ts = match parse("2024-07-04", ISO8601_DATE) {
///     Result::Ok(t) => t,
///     Result::Err(_) => panic "parse",
/// };
/// assert!((format(ts, ISO8601_DATE).ok() ?? "") == "2024-07-04");
/// ```
const ISO8601_DATE = "%Y-%m-%d";
// Date-time body without fraction or zone. Use `format_iso8601` / `format_rfc3339` for `Z`.
/// `format` / `parse` pattern for an ISO 8601 date-time body, `YYYY-MM-DDTHH:MM:SS`.
///
/// It has no fraction and no zone. Use `format_rfc3339` / `format_iso8601` for
/// output with a `Z` suffix, and `parse_rfc3339` / `parse_iso8601` to read
/// fractions and offsets.
///
/// # Examples
///
/// ```
/// use time::{parse, format_rfc3339, ISO8601};
/// # use tests::assert;
/// let ts = match parse("2024-03-01T12:30:00", ISO8601) {
///     Result::Ok(t) => t,
///     Result::Err(_) => panic "parse",
/// };
/// assert!((format_rfc3339(ts).ok() ?? "") == "2024-03-01T12:30:00Z");
/// ```
const ISO8601 = "%Y-%m-%dT%H:%M:%S";

/// Error returned by every fallible function in `time`.
///
/// # Examples
///
/// ```
/// use time::{sleep_ms, TimeError};
/// # use tests::assert;
/// let invalid = match sleep_ms(-1) {
///     Result::Ok(_) => false,
///     Result::Err(e) => match e {
///         TimeError::InvalidInput => true,
///         default => false,
///     },
/// };
/// assert!(invalid);
/// ```
enum TimeError {
    /// An argument is out of range: a negative sleep, a zero month or day, an
    /// impossible date, an unknown `format` directive, or an `Instant` that was dropped.
    InvalidInput,
    /// A result or an intermediate value does not fit in a 64-bit `int`.
    Overflow,
    /// The text does not match the expected format, or names an impossible date or time.
    ParseError,
    /// Any other failure, such as output that is not valid UTF-8.
    Other,
}

/// A point in time, measured from the Unix epoch (1970-01-01T00:00:00Z, UTC).
///
/// The same instant is available at four scales: `secs`, `millis`, `micros` and
/// `nanos`. Coarser scales round toward negative infinity, so times before the
/// epoch have negative values. A `Timestamp` has no time zone; formatting and
/// calendar math are always in UTC.
///
/// Get one from `timestamp` (now), `date` (today at midnight), `epoch`, the
/// `parse_*` functions, or `add` / `sub` on another `Timestamp`.
///
/// # Examples
///
/// ```
/// use time::{parse_rfc3339, Timestamp};
/// # use tests::assert;
/// let secs = parse_rfc3339("2024-01-01T00:00:01.5Z").map(fn (Timestamp t) => t.secs()).unwrap_or(0);
/// assert!(secs == 1704067201);
/// let millis = parse_rfc3339("2024-01-01T00:00:01.5Z").map(fn (Timestamp t) => t.millis()).unwrap_or(0);
/// assert!(millis == 1704067201500);
/// ```
class Timestamp {
    secs: int,
    millis: int,
    micros: int,
    nanos: int,
}

/// An amount of time as nine independent fields, from `years` down to `nanos`.
///
/// Fields are not normalized: `period(0, 0, 0, 0, 90, 0, 0, 0, 0)` stays ninety
/// minutes and is not turned into an hour and a half. Any field may be negative.
/// `add` applies `years` and `months` on the calendar first, then the fixed-length
/// fields (days and smaller) as an exact number of nanoseconds.
///
/// Build one with `period`; combine with `period_add` / `period_sub`.
///
/// # Examples
///
/// ```
/// use time::{period, period_add};
/// # use tests::assert;
/// let day = match period(0, 0, 1, 0, 0, 0, 0, 0, 0) {
///     Result::Ok(p) => p,
///     Result::Err(_) => panic "period",
/// };
/// let hours = match period(0, 0, 0, 6, 0, 0, 0, 0, 0) {
///     Result::Ok(p) => p,
///     Result::Err(_) => panic "period",
/// };
/// let total = match period_add(day, hours) {
///     Result::Ok(p) => p,
///     Result::Err(_) => panic "period_add",
/// };
/// assert!(total.days() == 1 && total.hours() == 6);
/// ```
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

/// A reading of the process's monotonic clock, for measuring elapsed time.
///
/// The monotonic clock never goes backwards and is not affected by changes to
/// the wall clock, so use `Instant` (not `timestamp`) to time work. Take one
/// with `instant_now` and read it with `elapsed_nanos` / `elapsed_millis`.
/// After `drop`, elapsed reads return `TimeError::InvalidInput`.
///
/// # Examples
///
/// ```
/// use time::{instant_now, sleep_ms};
/// # use tests::assert;
/// let start = instant_now();
/// sleep_ms(5).unwrap_or(());
/// assert!(start.elapsed_millis().unwrap_or(0) >= 5);
/// ```
class Instant {
    snapshot: int,
    live: int,
}

class Civil {
    pub year: int,
    pub month: int,
    pub day: int,
    pub hour: int,
    pub minute: int,
    pub second: int,
    pub nano: int,
}

class IntPair {
    pub a: int,
    pub b: int,
}

fn add_i(int a, int b) -> Result<int, TimeError> {
    if b > 0 {
        if a > i64_max() - b {
            raise TimeError::Overflow;
        }
    }
    if b < 0 {
        if a < i64_min() - b {
            raise TimeError::Overflow;
        }
    }
    return a + b;
}

fn sub_i(int a, int b) -> Result<int, TimeError> {
    if b > 0 {
        if a < i64_min() + b {
            raise TimeError::Overflow;
        }
    }
    if b < 0 {
        if a > i64_max() + b {
            raise TimeError::Overflow;
        }
    }
    return a - b;
}

fn mul_i(int a, int b) -> Result<int, TimeError> {
    if a == 0 || b == 0 {
        return 0;
    }
    if a == i64_min() {
        if b == 1 {
            return i64_min();
        }
        raise TimeError::Overflow;
    }
    if b == i64_min() {
        if a == 1 {
            return i64_min();
        }
        raise TimeError::Overflow;
    }
    let sa = 1;
    let sb = 1;
    let ua = a;
    let ub = b;
    if a < 0 {
        sa = -1;
        ua = 0 - a;
    }
    if b < 0 {
        sb = -1;
        ub = 0 - b;
    }
    if ua > i64_max() / ub {
        raise TimeError::Overflow;
    }
    let prod = ua * ub;
    if sa != sb {
        return 0 - prod;
    }
    return prod;
}

fn neg_i(int n) -> Result<int, TimeError> {
    if n == i64_min() {
        raise TimeError::Overflow;
    }
    return 0 - n;
}

fn floor_div(int a, int b) -> int {
    let q = a / b;
    let r = a % b;
    if r != 0 && ((a < 0 && b > 0) || (a > 0 && b < 0)) {
        return q - 1;
    }
    return q;
}

fn floor_mod(int a, int b) -> int {
    return a - floor_div(a, b) * b;
}

fn is_leap(int y) -> bool {
    if y % 400 == 0 {
        return true;
    }
    if y % 100 == 0 {
        return false;
    }
    return y % 4 == 0;
}

fn month_len(int y, int m) -> int {
    if m == 1 || m == 3 || m == 5 || m == 7 || m == 8 || m == 10 || m == 12 {
        return 31;
    }
    if m == 4 || m == 6 || m == 9 || m == 11 {
        return 30;
    }
    if is_leap(y) {
        return 29;
    }
    return 28;
}

fn valid_ymd(int y, int m, int d) -> bool {
    if m < 1 || m > 12 || d < 1 {
        return false;
    }
    return d <= month_len(y, m);
}

fn days_from_civil(int year, int month, int day) -> int {
    let y = year;
    if month <= 2 {
        y = y - 1;
    }
    let era = y / 400;
    if y < 0 {
        era = (y - 399) / 400;
    }
    let yoe = y - era * 400;
    let adj = month + 9;
    if month > 2 {
        adj = month - 3;
    }
    let doy = (153 * adj + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + doe - 719468;
}

fn civil_ymd(int z) -> Civil {
    let zz = z + 719468;
    let era = zz / 146097;
    if zz < 0 {
        era = (zz - 146096) / 146097;
    }
    let doe = zz - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = mp + 3;
    if mp >= 10 {
        m = mp - 9;
    }
    let year = y;
    if m <= 2 {
        year = y + 1;
    }
    return new Civil(year, m, d, 0, 0, 0, 0);
}

fn timestamp_from_nanos(int nanos) -> Timestamp {
    return new Timestamp(floor_div(nanos, NS_PER_SEC), floor_div(nanos, NS_PER_MS), floor_div(nanos, NS_PER_US), nanos);
}

fn civil_from_nanos(int nanos) -> Result<Civil, TimeError> {
    let days = floor_div(nanos, NS_PER_DAY);
    let day_ns = floor_mod(nanos, NS_PER_DAY);
    let c = civil_ymd(days);
    c.hour = day_ns / NS_PER_HOUR;
    let rem = day_ns % NS_PER_HOUR;
    c.minute = rem / NS_PER_MIN;
    rem = rem % NS_PER_MIN;
    c.second = rem / NS_PER_SEC;
    c.nano = rem % NS_PER_SEC;
    return c;
}

fn civil_to_timestamp(int year, int month, int day, int hour, int minute, int second, int nano) -> Result<Timestamp, TimeError> {
    let days = days_from_civil(year, month, day);
    let acc = mul_i(days, NS_PER_DAY)?;
    acc = add_i(acc, mul_i(hour, NS_PER_HOUR)?)?;
    acc = add_i(acc, mul_i(minute, NS_PER_MIN)?)?;
    acc = add_i(acc, mul_i(second, NS_PER_SEC)?)?;
    acc = add_i(acc, nano)?;
    return timestamp_from_nanos(acc);
}

fn add_months_civil(Civil c, int month_delta) -> Result<Civil, TimeError> {
    if month_delta == 0 {
        return c;
    }
    let total = add_i(mul_i(c.year, 12)?, c.month - 1)?;
    total = add_i(total, month_delta)?;
    let year = floor_div(total, 12);
    let month = floor_mod(total, 12) + 1;
    let dim = month_len(year, month);
    let day = c.day;
    if day > dim {
        day = dim;
    }
    return new Civil(year, month, day, c.hour, c.minute, c.second, c.nano);
}

fn period_time_nanos(Period p) -> Result<int, TimeError> {
    let acc = mul_i(p.days(), NS_PER_DAY)?;
    acc = add_i(acc, mul_i(p.hours(), NS_PER_HOUR)?)?;
    acc = add_i(acc, mul_i(p.minutes(), NS_PER_MIN)?)?;
    acc = add_i(acc, mul_i(p.secs(), NS_PER_SEC)?)?;
    acc = add_i(acc, mul_i(p.millis(), NS_PER_MS)?)?;
    acc = add_i(acc, mul_i(p.micros(), NS_PER_US)?)?;
    acc = add_i(acc, p.nanos())?;
    return acc;
}

fn apply_period(int nanos, Period p) -> Result<int, TimeError> {
    let month_delta = add_i(mul_i(p.years(), 12)?, p.months())?;
    let c = civil_from_nanos(nanos)?;
    c = add_months_civil(c, month_delta)?;
    let base = civil_to_timestamp(c.year, c.month, c.day, c.hour, c.minute, c.second, c.nano)?;
    let delta = period_time_nanos(p)?;
    let out = add_i(base.nanos(), delta)?;
    return out;
}

fn negate_period(Period p) -> Result<Period, TimeError> {
    let years = neg_i(p.years())?;
    let months = neg_i(p.months())?;
    let days = neg_i(p.days())?;
    let hours = neg_i(p.hours())?;
    let minutes = neg_i(p.minutes())?;
    let secs = neg_i(p.secs())?;
    let millis = neg_i(p.millis())?;
    let micros = neg_i(p.micros())?;
    let nanos = neg_i(p.nanos())?;
    return new Period(years, months, days, hours, minutes, secs, millis, micros, nanos);
}

fn pad2(int n) -> string {
    if n < 10 {
        return "0" + sfmt("%i", n);
    }
    return sfmt("%i", n);
}

fn pad4(int n) -> string {
    let s = sfmt("%i", n);
    if n < 10 {
        return "000" + s;
    }
    if n < 100 {
        return "00" + s;
    }
    if n < 1000 {
        return "0" + s;
    }
    return s;
}

fn year_text(int y) -> string {
    if y < 0 {
        return "-" + pad4(0 - y);
    }
    return pad4(y);
}

fn digit(int b) -> int {
    if b >= 48 && b <= 57 {
        return b - 48;
    }
    return -1;
}

fn parse_two_digits(Vec<byte> text, int pos, int n) -> Result<IntPair, TimeError> {
    if pos + 2 > n {
        raise TimeError::ParseError;
    }
    let a = digit(text[pos] as int);
    let b = digit(text[pos + 1] as int);
    if a < 0 || b < 0 {
        raise TimeError::ParseError;
    }
    return new IntPair(a * 10 + b, pos + 2);
}

fn parse_year(Vec<byte> text, int pos, int n) -> Result<IntPair, TimeError> {
    let i = pos;
    let sign = 1;
    if i < n && (text[i] as int) == 45 {
        sign = -1;
        i = i + 1;
    }
    if i + 4 > n {
        raise TimeError::ParseError;
    }
    let acc = 0;
    let k = 0;
    while k < 4 {
        let d = digit(text[i] as int);
        if d < 0 {
            raise TimeError::ParseError;
        }
        acc = acc * 10 + d;
        i = i + 1;
        k = k + 1;
    }
    return new IntPair(sign * acc, i);
}

fn bytes_eq_at(Vec<byte> text, int pos, int n, string lit) -> bool {
    let lb = to_bytes(lit);
    let ln = lb.len();
    if pos + ln > n {
        return false;
    }
    let i = 0;
    while i < ln {
        if (text[pos + i] as int) != (lb[i] as int) {
            return false;
        }
        i = i + 1;
    }
    return true;
}

fn expect_lit(Vec<byte> text, int pos, int n, string lit) -> Result<int, TimeError> {
    if bytes_eq_at(text, pos, n, lit) {
        return pos + to_bytes(lit).len();
    }
    raise TimeError::ParseError;
}

fn expect_byte(Vec<byte> text, int pos, int n, int want) -> Result<int, TimeError> {
    if pos >= n {
        raise TimeError::ParseError;
    }
    if (text[pos] as int) != want {
        raise TimeError::ParseError;
    }
    return pos + 1;
}

fn string_from_bytes(Vec<byte> buf) -> Result<string, TimeError> {
    return match from_bytes(buf) {
        Result::Ok(s) => s,
        Result::Err(_) => raise TimeError::Other,
    };
}

fn pad9(int n) -> Result<string, TimeError> {
    let out: Vec<byte> = Vec::new();
    let rest = n;
    let div = 100000000;
    let i = 0;
    while i < 9 {
        let d = rest / div;
        rest = rest % div;
        let ch = 48 + d;
        out.push(ch as byte);
        div = div / 10;
        i = i + 1;
    }
    let s = string_from_bytes(out)?;
    return s;
}

fn frac_digits(int nano) -> Result<string, TimeError> {
    let s = pad9(nano)?;
    let b = to_bytes(s);
    let end = 9;
    while end > 1 {
        if (b[end - 1] as int) != 48 {
            break;
        }
        end = end - 1;
    }
    let out: Vec<byte> = Vec::new();
    let i = 0;
    while i < end {
        out.push(b[i]);
        i = i + 1;
    }
    let s = string_from_bytes(out)?;
    return s;
}

fn parse_frac_nanos(Vec<byte> text, int pos, int n) -> Result<IntPair, TimeError> {
    let acc = 0;
    let count = 0;
    let i = pos;
    while i < n {
        let d = digit(text[i] as int);
        if d < 0 {
            break;
        }
        if count >= 9 {
            raise TimeError::ParseError;
        }
        acc = acc * 10 + d;
        count = count + 1;
        i = i + 1;
    }
    if count == 0 {
        raise TimeError::ParseError;
    }
    let p = 1;
    let k = 0;
    while k < (9 - count) {
        p = p * 10;
        k = k + 1;
    }
    return new IntPair(acc * p, i);
}

fn timestamp_from_hms(int year, int month, int day, int hour, int minute, int second, int nano) -> Result<Timestamp, TimeError> {
    if hour > 23 || minute > 59 || second > 59 {
        raise TimeError::ParseError;
    }
    if nano < 0 || nano > 999999999 {
        raise TimeError::ParseError;
    }
    let ok = valid_ymd(year, month, day);
    if ok == false {
        raise TimeError::ParseError;
    }
    let ts = civil_to_timestamp(year, month, day, hour, minute, second, nano)?;
    return ts;
}

fn apply_offset_minutes(Timestamp ts, int offset_min) -> Result<Timestamp, TimeError> {
    let delta = mul_i(offset_min, NS_PER_MIN)?;
    let out = sub_i(ts.nanos(), delta)?;
    return timestamp_from_nanos(out);
}

fn parse_hhmm(Vec<byte> text, int pos, int n, bool colon) -> Result<IntPair, TimeError> {
    let pair = parse_two_digits(text, pos, n)?;
    let hour = pair.a;
    let i = pair.b;
    if colon {
        i = expect_byte(text, i, n, 58)?;
    }
    pair = parse_two_digits(text, i, n)?;
    let minute = pair.a;
    if hour > 23 || minute > 59 {
        raise TimeError::ParseError;
    }
    return new IntPair(hour * 60 + minute, pair.b);
}

fn weekday_sun0(int year, int month, int day) -> int {
    return floor_mod(days_from_civil(year, month, day) + 4, 7);
}

fn weekday_name(int wd) -> string {
    if wd == 0 {
        return "Sun";
    }
    if wd == 1 {
        return "Mon";
    }
    if wd == 2 {
        return "Tue";
    }
    if wd == 3 {
        return "Wed";
    }
    if wd == 4 {
        return "Thu";
    }
    if wd == 5 {
        return "Fri";
    }
    return "Sat";
}

fn month_name(int m) -> string {
    if m == 1 {
        return "Jan";
    }
    if m == 2 {
        return "Feb";
    }
    if m == 3 {
        return "Mar";
    }
    if m == 4 {
        return "Apr";
    }
    if m == 5 {
        return "May";
    }
    if m == 6 {
        return "Jun";
    }
    if m == 7 {
        return "Jul";
    }
    if m == 8 {
        return "Aug";
    }
    if m == 9 {
        return "Sep";
    }
    if m == 10 {
        return "Oct";
    }
    if m == 11 {
        return "Nov";
    }
    return "Dec";
}

fn parse_weekday_name(Vec<byte> text, int pos, int n) -> Result<IntPair, TimeError> {
    if bytes_eq_at(text, pos, n, "Sun") {
        return new IntPair(0, pos + 3);
    }
    if bytes_eq_at(text, pos, n, "Mon") {
        return new IntPair(1, pos + 3);
    }
    if bytes_eq_at(text, pos, n, "Tue") {
        return new IntPair(2, pos + 3);
    }
    if bytes_eq_at(text, pos, n, "Wed") {
        return new IntPair(3, pos + 3);
    }
    if bytes_eq_at(text, pos, n, "Thu") {
        return new IntPair(4, pos + 3);
    }
    if bytes_eq_at(text, pos, n, "Fri") {
        return new IntPair(5, pos + 3);
    }
    if bytes_eq_at(text, pos, n, "Sat") {
        return new IntPair(6, pos + 3);
    }
    raise TimeError::ParseError;
}

fn parse_month_name(Vec<byte> text, int pos, int n) -> Result<IntPair, TimeError> {
    if bytes_eq_at(text, pos, n, "Jan") {
        return new IntPair(1, pos + 3);
    }
    if bytes_eq_at(text, pos, n, "Feb") {
        return new IntPair(2, pos + 3);
    }
    if bytes_eq_at(text, pos, n, "Mar") {
        return new IntPair(3, pos + 3);
    }
    if bytes_eq_at(text, pos, n, "Apr") {
        return new IntPair(4, pos + 3);
    }
    if bytes_eq_at(text, pos, n, "May") {
        return new IntPair(5, pos + 3);
    }
    if bytes_eq_at(text, pos, n, "Jun") {
        return new IntPair(6, pos + 3);
    }
    if bytes_eq_at(text, pos, n, "Jul") {
        return new IntPair(7, pos + 3);
    }
    if bytes_eq_at(text, pos, n, "Aug") {
        return new IntPair(8, pos + 3);
    }
    if bytes_eq_at(text, pos, n, "Sep") {
        return new IntPair(9, pos + 3);
    }
    if bytes_eq_at(text, pos, n, "Oct") {
        return new IntPair(10, pos + 3);
    }
    if bytes_eq_at(text, pos, n, "Nov") {
        return new IntPair(11, pos + 3);
    }
    if bytes_eq_at(text, pos, n, "Dec") {
        return new IntPair(12, pos + 3);
    }
    raise TimeError::ParseError;
}

fn format_civil_rfc3339(Civil c) -> Result<string, TimeError> {
    let body = year_text(c.year) + "-" + pad2(c.month) + "-" + pad2(c.day) + "T" + pad2(c.hour) + ":" + pad2(c.minute) + ":" + pad2(c.second);
    if c.nano == 0 {
        return body + "Z";
    }
    let frac = frac_digits(c.nano)?;
    return body + "." + frac + "Z";
}

fn parse_iso_datetime(string text, bool require_zone) -> Result<Timestamp, TimeError> {
    let tb = to_bytes(text);
    let n = tb.len();
    let pair = parse_year(tb, 0, n)?;
    let year = pair.a;
    let i = expect_byte(tb, pair.b, n, 45)?;
    pair = parse_two_digits(tb, i, n)?;
    let month = pair.a;
    i = expect_byte(tb, pair.b, n, 45)?;
    pair = parse_two_digits(tb, i, n)?;
    let day = pair.a;
    i = pair.b;
    if i >= n {
        raise TimeError::ParseError;
    }
    let sep = tb[i] as int;
    if sep != 84 && sep != 32 {
        raise TimeError::ParseError;
    }
    i = i + 1;
    pair = parse_two_digits(tb, i, n)?;
    let hour = pair.a;
    i = expect_byte(tb, pair.b, n, 58)?;
    pair = parse_two_digits(tb, i, n)?;
    let minute = pair.a;
    i = expect_byte(tb, pair.b, n, 58)?;
    pair = parse_two_digits(tb, i, n)?;
    let second = pair.a;
    i = pair.b;
    let nano = 0;
    if i < n {
        if (tb[i] as int) == 46 {
            pair = parse_frac_nanos(tb, i + 1, n)?;
            nano = pair.a;
            i = pair.b;
        }
    }
    let offset_min = 0;
    let saw_zone = false;
    if i < n {
        let z = tb[i] as int;
        if z == 90 || z == 122 {
            saw_zone = true;
            i = i + 1;
        } else {
            if z == 43 || z == 45 {
                saw_zone = true;
                let sign = 1;
                if z == 45 {
                    sign = -1;
                }
                i = i + 1;
                let colon = false;
                if i + 2 < n {
                    if (tb[i + 2] as int) == 58 {
                        colon = true;
                    }
                }
                if require_zone {
                    if colon == false {
                        raise TimeError::ParseError;
                    }
                }
                pair = parse_hhmm(tb, i, n, colon)?;
                offset_min = sign * pair.a;
                i = pair.b;
            }
        }
    }
    if require_zone && saw_zone == false {
        raise TimeError::ParseError;
    }
    if i != n {
        raise TimeError::ParseError;
    }
    let ts = timestamp_from_hms(year, month, day, hour, minute, second, nano)?;
    let out = apply_offset_minutes(ts, offset_min)?;
    return out;
}

/// The current wall-clock time (UTC) as a `Timestamp`.
///
/// The wall clock can jump (NTP, manual changes); use `instant_now` to measure
/// durations.
///
/// # Examples
///
/// ```
/// use time::{timestamp, Timestamp};
/// # use tests::assert;
/// let secs = timestamp().map(fn (Timestamp t) => t.secs()).unwrap_or(0);
/// assert!(secs > 1704067200);
/// ```
fn timestamp() -> Result<Timestamp, TimeError> {
    let nanos = wall_nanos();
    return timestamp_from_nanos(nanos);
}

/// Block the current task for at least `millis` milliseconds.
///
/// `sleep_ms(0)` returns at once. A negative `millis` is `TimeError::InvalidInput`.
///
/// # Examples
///
/// ```
/// use time::{sleep_ms};
/// # use tests::assert;
/// assert!(sleep_ms(1).is_ok());
/// assert!(sleep_ms(-1).is_err());
/// ```
fn sleep_ms(int millis) -> Result<(), TimeError> {
    if millis < 0 {
        raise TimeError::InvalidInput;
    }
    host_sleep_ms(millis);
    return ();
}

/// Take a monotonic clock reading now.
///
/// # Examples
///
/// ```
/// use time::{instant_now, elapsed_nanos};
/// # use tests::assert;
/// let start = instant_now();
/// assert!(elapsed_nanos(start).unwrap_or(-1) >= 0);
/// ```
fn instant_now() -> Instant {
    let snap = mono_nanos();
    let inst = new Instant(snap, 1);
    return inst;
}

/// Nanoseconds since `inst` was taken. Same as `inst.elapsed_nanos()`.
///
/// Returns `TimeError::InvalidInput` when `inst` was dropped.
fn elapsed_nanos(Instant inst) -> Result<int, TimeError> {
    return match inst.elapsed_nanos() {
        Result::Ok(n) => n,
        Result::Err(e) => raise e,
    };
}

/// Whole milliseconds since `inst` was taken. Same as `inst.elapsed_millis()`.
///
/// Returns `TimeError::InvalidInput` when `inst` was dropped.
fn elapsed_millis(Instant inst) -> Result<int, TimeError> {
    return match inst.elapsed_millis() {
        Result::Ok(n) => n,
        Result::Err(e) => raise e,
    };
}

/// Build a `Period` from its nine fields, largest first.
///
/// Fields are stored as given (no normalization, negatives allowed). It always
/// returns `Ok` today; the `Result` leaves room for validation.
///
/// # Examples
///
/// ```
/// use time::{period, Period};
/// # use tests::assert;
/// let p = period(1, 2, 3, 0, 0, 0, 0, 0, 0);
/// assert!(p.map(fn (Period p) => p.years() == 1 && p.months() == 2 && p.days() == 3).unwrap_or(false));
/// ```
fn period(int years, int months, int days, int hours, int minutes, int secs, int millis, int micros, int nanos) -> Result<Period, TimeError> {
    return new Period(years, months, days, hours, minutes, secs, millis, micros, nanos);
}

/// `ts` moved forward by `p`.
///
/// `years` and `months` move the calendar date first (UTC), keeping the time of
/// day; when the day does not exist in the target month it is clamped to the
/// last day (Jan 31 plus one month is Feb 28 or 29). The remaining fields are
/// then added as an exact duration. Returns `TimeError::Overflow` when the
/// result does not fit.
///
/// # Examples
///
/// ```
/// use time::{add, parse_iso8601_date, format_iso8601_date, period};
/// # use tests::assert;
/// let month = match period(0, 1, 0, 0, 0, 0, 0, 0, 0) {
///     Result::Ok(p) => p,
///     Result::Err(_) => panic "period",
/// };
/// let jan31 = match parse_iso8601_date("2024-01-31") {
///     Result::Ok(t) => t,
///     Result::Err(_) => panic "parse",
/// };
/// let next = match add(jan31, month) {
///     Result::Ok(t) => t,
///     Result::Err(_) => panic "add",
/// };
/// assert!((format_iso8601_date(next).ok() ?? "") == "2024-02-29");
/// ```
fn add(Timestamp ts, Period p) -> Result<Timestamp, TimeError> {
    let out = apply_period(ts.nanos(), p)?;
    return timestamp_from_nanos(out);
}

/// `ts` moved back by `p`: `add` with every field of `p` negated.
///
/// Returns `TimeError::Overflow` when a field cannot be negated or the result
/// does not fit.
///
/// # Examples
///
/// ```
/// use time::{sub, parse_rfc3339, format_rfc3339, period};
/// # use tests::assert;
/// let day = match period(0, 0, 1, 0, 0, 0, 0, 0, 0) {
///     Result::Ok(p) => p,
///     Result::Err(_) => panic "period",
/// };
/// let mar1 = match parse_rfc3339("2024-03-01T08:00:00Z") {
///     Result::Ok(t) => t,
///     Result::Err(_) => panic "parse",
/// };
/// let prev = match sub(mar1, day) {
///     Result::Ok(t) => t,
///     Result::Err(_) => panic "sub",
/// };
/// assert!((format_rfc3339(prev).ok() ?? "") == "2024-02-29T08:00:00Z");
/// ```
fn sub(Timestamp ts, Period p) -> Result<Timestamp, TimeError> {
    let neg = negate_period(p)?;
    let out = apply_period(ts.nanos(), neg)?;
    return timestamp_from_nanos(out);
}

/// Field-by-field sum of two periods (no normalization).
///
/// Returns `TimeError::Overflow` when any field overflows.
fn period_add(Period a, Period b) -> Result<Period, TimeError> {
    // `?` on Result<int> drops Overflow; match/raise keeps the tag.
    let years = match add_i(a.years(), b.years()) {
        Result::Ok(n) => n,
        Result::Err(e) => raise e,
    };
    let months = add_i(a.months(), b.months())?;
    let days = add_i(a.days(), b.days())?;
    let hours = add_i(a.hours(), b.hours())?;
    let minutes = add_i(a.minutes(), b.minutes())?;
    let secs = add_i(a.secs(), b.secs())?;
    let millis = add_i(a.millis(), b.millis())?;
    let micros = add_i(a.micros(), b.micros())?;
    let nanos = add_i(a.nanos(), b.nanos())?;
    return new Period(years, months, days, hours, minutes, secs, millis, micros, nanos);
}

/// Field-by-field difference `a - b` (no normalization).
///
/// Returns `TimeError::Overflow` when any field overflows.
fn period_sub(Period a, Period b) -> Result<Period, TimeError> {
    let years = sub_i(a.years(), b.years())?;
    let months = sub_i(a.months(), b.months())?;
    let days = sub_i(a.days(), b.days())?;
    let hours = sub_i(a.hours(), b.hours())?;
    let minutes = sub_i(a.minutes(), b.minutes())?;
    let secs = sub_i(a.secs(), b.secs())?;
    let millis = sub_i(a.millis(), b.millis())?;
    let micros = sub_i(a.micros(), b.micros())?;
    let nanos = sub_i(a.nanos(), b.nanos())?;
    return new Period(years, months, days, hours, minutes, secs, millis, micros, nanos);
}

/// Today's date: the current wall-clock time truncated to midnight UTC.
///
/// # Examples
///
/// ```
/// use time::{date, format};
/// # use tests::assert;
/// let today = match date() {
///     Result::Ok(t) => t,
///     Result::Err(_) => panic "date",
/// };
/// assert!((format(today, "%H:%M:%S").ok() ?? "") == "00:00:00");
/// ```
fn date() -> Result<Timestamp, TimeError> {
    let nanos = wall_nanos();
    let days = floor_div(nanos, NS_PER_DAY);
    let midnight = mul_i(days, NS_PER_DAY)?;
    return timestamp_from_nanos(midnight);
}

/// Midnight UTC of the calendar date `p.years()`-`p.months()`-`p.days()`.
///
/// `p` is read as a year, month (1-12) and day (1-31); its smaller fields are
/// ignored. A zero month or day, a month above 12 or a day past the month's end
/// is `TimeError::InvalidInput`. A negative month or day, or a year outside the
/// 32-bit range, is `TimeError::Overflow`.
///
/// # Examples
///
/// ```
/// use time::{date_from_period, period, format_iso8601_date};
/// # use tests::assert;
/// let leap_day = match period(2024, 2, 29, 0, 0, 0, 0, 0, 0) {
///     Result::Ok(p) => p,
///     Result::Err(_) => panic "period",
/// };
/// let ts = match date_from_period(leap_day) {
///     Result::Ok(t) => t,
///     Result::Err(_) => panic "date_from_period",
/// };
/// assert!((format_iso8601_date(ts).ok() ?? "") == "2024-02-29");
/// let no_such_day = match period(2023, 2, 29, 0, 0, 0, 0, 0, 0) {
///     Result::Ok(p) => p,
///     Result::Err(_) => panic "period",
/// };
/// assert!(date_from_period(no_such_day).is_err());
/// ```
fn date_from_period(Period p) -> Result<Timestamp, TimeError> {
    if p.years() < I32_MIN || p.years() > I32_MAX {
        raise TimeError::Overflow;
    }
    if p.months() < 0 || p.days() < 0 {
        raise TimeError::Overflow;
    }
    if p.months() == 0 || p.days() == 0 {
        raise TimeError::InvalidInput;
    }
    let ok = valid_ymd(p.years(), p.months(), p.days());
    if p.months() > 12 || ok == false {
        raise TimeError::InvalidInput;
    }
    let days = days_from_civil(p.years(), p.months(), p.days());
    let nanos = mul_i(days, NS_PER_DAY)?;
    return timestamp_from_nanos(nanos);
}

/// The Unix epoch moved forward by `p`; same as `add(epoch, p)`.
///
/// # Examples
///
/// ```
/// use time::{date_from_epoch_period, period, Timestamp};
/// # use tests::assert;
/// let day = match period(0, 0, 1, 0, 0, 0, 0, 0, 0) {
///     Result::Ok(p) => p,
///     Result::Err(_) => panic "period",
/// };
/// let secs = date_from_epoch_period(day).map(fn (Timestamp t) => t.secs()).unwrap_or(0);
/// assert!(secs == 86400);
/// ```
fn date_from_epoch_period(Period p) -> Result<Timestamp, TimeError> {
    let out = apply_period(0, p)?;
    return timestamp_from_nanos(out);
}

/// The Unix epoch, 1970-01-01T00:00:00Z: a `Timestamp` with every scale at zero.
///
/// # Examples
///
/// ```
/// use time::{epoch, format_rfc3339};
/// # use tests::assert;
/// let zero = match epoch() {
///     Result::Ok(t) => t,
///     Result::Err(_) => panic "epoch",
/// };
/// assert!((format_rfc3339(zero).ok() ?? "") == "1970-01-01T00:00:00Z");
/// ```
fn epoch() -> Result<Timestamp, TimeError> {
    return timestamp_from_nanos(0);
}

fn format_spec(Civil c, int spec) -> Result<string, TimeError> {
    if spec == 37 {
        return "%";
    }
    if spec == 89 {
        return year_text(c.year);
    }
    if spec == 109 {
        return pad2(c.month);
    }
    if spec == 100 {
        return pad2(c.day);
    }
    if spec == 72 {
        return pad2(c.hour);
    }
    if spec == 77 {
        return pad2(c.minute);
    }
    if spec == 83 {
        return pad2(c.second);
    }
    raise TimeError::InvalidInput;
}

fn append_bytes(Vec<byte> dest, Vec<byte> src) {
    let n = src.len();
    let i = 0;
    while i < n {
        dest.push(src[i]);
        i = i + 1;
    }
}

/// Format `ts` (in UTC) with a `strftime`-style pattern.
///
/// Directives: `%Y` year (at least four digits, `-` for years before 0),
/// `%m` month, `%d` day, `%H` hour, `%M` minute, `%S` second (all two digits),
/// and `%%` for a literal `%`. Every other byte is copied as is. Sub-second
/// digits are not printed. An unknown directive or a trailing `%` is
/// `TimeError::InvalidInput`. `ISO8601_DATE` and `ISO8601` are ready-made patterns.
///
/// # Examples
///
/// ```
/// use time::{format, parse_rfc3339};
/// # use tests::assert;
/// let ts = match parse_rfc3339("2024-07-04T09:05:00Z") {
///     Result::Ok(t) => t,
///     Result::Err(_) => panic "parse",
/// };
/// assert!((format(ts, "%d/%m/%Y %H:%M (100%%)").ok() ?? "") == "04/07/2024 09:05 (100%)");
/// ```
fn format(Timestamp ts, string fmt) -> Result<string, TimeError> {
    let c = civil_from_nanos(ts.nanos())?;
    let fb = to_bytes(fmt);
    let n = fb.len();
    let out: Vec<byte> = Vec::new();
    let i = 0;
    while i < n {
        let b = fb[i] as int;
        if b != 37 {
            out.push(b as byte);
            i = i + 1;
        } else {
            if i + 1 >= n {
                raise TimeError::InvalidInput;
            }
            let piece = format_spec(c, fb[i + 1] as int)?;
            append_bytes(out, to_bytes(piece));
            i = i + 2;
        }
    }
    return match from_bytes(out) {
        Result::Ok(s) => s,
        Result::Err(_) => raise TimeError::Other,
    };
}

/// Parse `text` as a UTC time laid out by the pattern `fmt`.
///
/// Accepts the same directives as `format`. `%Y` reads exactly four digits
/// (with an optional leading `-`); the others read exactly two. Missing fields
/// default to 1970-01-01 00:00:00. Literal bytes must match exactly and the whole
/// of `text` must be consumed. Any mismatch, an unknown directive, or an
/// impossible date or time is `TimeError::ParseError`.
///
/// # Examples
///
/// ```
/// use time::{parse, Timestamp};
/// # use tests::assert;
/// let secs = parse("2024-01-01 00:00:00", "%Y-%m-%d %H:%M:%S").map(fn (Timestamp t) => t.secs()).unwrap_or(0);
/// assert!(secs == 1704067200);
/// assert!(parse("2024-02-30", "%Y-%m-%d").is_err());
/// ```
fn parse(string text, string fmt) -> Result<Timestamp, TimeError> {
    let tb = to_bytes(text);
    let fb = to_bytes(fmt);
    let tn = tb.len();
    let flen = fb.len();
    let ti = 0;
    let fi = 0;
    let year = 1970;
    let month = 1;
    let day = 1;
    let hour = 0;
    let minute = 0;
    let second = 0;
    while fi < flen {
        let b = fb[fi] as int;
        if b != 37 {
            if ti >= tn || (tb[ti] as int) != b {
                raise TimeError::ParseError;
            }
            ti = ti + 1;
            fi = fi + 1;
        } else {
            if fi + 1 >= flen {
                raise TimeError::ParseError;
            }
            let spec = fb[fi + 1] as int;
            if spec == 37 {
                if ti >= tn || (tb[ti] as int) != 37 {
                    raise TimeError::ParseError;
                }
                ti = ti + 1;
            } else {
                if spec == 89 {
                    let pair = parse_year(tb, ti, tn)?;
                    year = pair.a;
                    ti = pair.b;
                } else {
                    if spec == 109 {
                        let pair = parse_two_digits(tb, ti, tn)?;
                        month = pair.a;
                        ti = pair.b;
                    } else {
                        if spec == 100 {
                            let pair = parse_two_digits(tb, ti, tn)?;
                            day = pair.a;
                            ti = pair.b;
                        } else {
                            if spec == 72 {
                                let pair = parse_two_digits(tb, ti, tn)?;
                                hour = pair.a;
                                ti = pair.b;
                            } else {
                                if spec == 77 {
                                    let pair = parse_two_digits(tb, ti, tn)?;
                                    minute = pair.a;
                                    ti = pair.b;
                                } else {
                                    if spec == 83 {
                                        let pair = parse_two_digits(tb, ti, tn)?;
                                        second = pair.a;
                                        ti = pair.b;
                                    } else {
                                        raise TimeError::ParseError;
                                    }
                                }
                            }
                        }
                    }
                }
            }
            fi = fi + 2;
        }
    }
    if ti != tn {
        raise TimeError::ParseError;
    }
    if hour > 23 || minute > 59 || second > 59 {
        raise TimeError::ParseError;
    }
    let ok = valid_ymd(year, month, day);
    if ok == false {
        raise TimeError::ParseError;
    }
    let ts = civil_to_timestamp(year, month, day, hour, minute, second, 0)?;
    return ts;
}

/// Format `ts` as RFC 3339 in UTC, such as `2024-01-01T00:00:00Z`.
///
/// A non-zero sub-second part is printed as a fraction with trailing zeros
/// removed (`2024-01-01T00:00:00.123Z`).
///
/// # Examples
///
/// ```
/// use time::{format_rfc3339, parse_rfc3339};
/// # use tests::assert;
/// let ts = match parse_rfc3339("2024-01-15T12:30:00-05:00") {
///     Result::Ok(t) => t,
///     Result::Err(_) => panic "parse",
/// };
/// assert!((format_rfc3339(ts).ok() ?? "") == "2024-01-15T17:30:00Z");
/// ```
fn format_rfc3339(Timestamp ts) -> Result<string, TimeError> {
    let c = civil_from_nanos(ts.nanos())?;
    let s = format_civil_rfc3339(c)?;
    return s;
}

/// Parse an RFC 3339 date-time, such as `2024-01-01T00:00:00Z`.
///
/// Accepts `T` or a space between date and time, an optional fraction of up to
/// nine digits, and a zone of `Z`, `z` or `±HH:MM`. A missing zone, a
/// colon-less offset, or any other mismatch is `TimeError::ParseError`.
///
/// # Examples
///
/// ```
/// use time::{parse_rfc3339, Timestamp};
/// # use tests::assert;
/// let ms = parse_rfc3339("2024-01-01T00:00:00.250Z").map(fn (Timestamp t) => t.millis()).unwrap_or(0);
/// assert!(ms == 1704067200250);
/// assert!(parse_rfc3339("2024-01-01T00:00:00").is_err());
/// ```
fn parse_rfc3339(string text) -> Result<Timestamp, TimeError> {
    let ts = parse_iso_datetime(text, true)?;
    return ts;
}

/// Format `ts` as an ISO 8601 date-time in UTC; the output is the same as `format_rfc3339`.
fn format_iso8601(Timestamp ts) -> Result<string, TimeError> {
    let s = format_rfc3339(ts)?;
    return s;
}

/// Parse an ISO 8601 date-time, such as `2024-06-08T09:10:11`.
///
/// Like `parse_rfc3339`, but the zone is optional (no zone means UTC) and an
/// offset may be written `±HH:MM` or `±HHMM`. A bare date is
/// `TimeError::ParseError`; use `parse_iso8601_date` for that.
///
/// # Examples
///
/// ```
/// use time::{parse_iso8601, Timestamp};
/// # use tests::assert;
/// let a = parse_iso8601("2024-06-08T09:10:11").map(fn (Timestamp t) => t.secs()).unwrap_or(0);
/// let b = parse_iso8601("2024-06-08T11:10:11+0200").map(fn (Timestamp t) => t.secs()).unwrap_or(1);
/// assert!(a == b);
/// ```
fn parse_iso8601(string text) -> Result<Timestamp, TimeError> {
    let ts = parse_iso_datetime(text, false)?;
    return ts;
}

/// Format the UTC calendar date of `ts` as `YYYY-MM-DD`; the time of day is dropped.
fn format_iso8601_date(Timestamp ts) -> Result<string, TimeError> {
    let s = format(ts, ISO8601_DATE)?;
    return s;
}

/// Parse a `YYYY-MM-DD` date as midnight UTC of that day.
///
/// Anything else, including a trailing time, is `TimeError::ParseError`.
///
/// # Examples
///
/// ```
/// use time::{parse_iso8601_date, Timestamp};
/// # use tests::assert;
/// assert!(parse_iso8601_date("1970-01-02").map(fn (Timestamp t) => t.secs()).unwrap_or(0) == 86400);
/// assert!(parse_iso8601_date("2024-01-01T00:00:00Z").is_err());
/// ```
fn parse_iso8601_date(string text) -> Result<Timestamp, TimeError> {
    let ts = parse(text, ISO8601_DATE)?;
    return ts;
}

/// Format `ts` as an RFC 2822 date in GMT, such as `Mon, 01 Jan 2024 00:00:00 GMT`.
///
/// The output is the IMF-fixdate form, so it is the same as `format_http_date`.
///
/// # Examples
///
/// ```
/// use time::{format_rfc2822, parse_rfc3339};
/// # use tests::assert;
/// let ts = match parse_rfc3339("1994-11-06T08:49:37Z") {
///     Result::Ok(t) => t,
///     Result::Err(_) => panic "parse",
/// };
/// assert!((format_rfc2822(ts).ok() ?? "") == "Sun, 06 Nov 1994 08:49:37 GMT");
/// ```
fn format_rfc2822(Timestamp ts) -> Result<string, TimeError> {
    let c = civil_from_nanos(ts.nanos())?;
    let wd = weekday_sun0(c.year, c.month, c.day);
    return weekday_name(wd) + ", " + pad2(c.day) + " " + month_name(c.month) + " " + year_text(c.year) + " " + pad2(c.hour) + ":" + pad2(c.minute) + ":" + pad2(c.second) + " GMT";
}

/// Format `ts` as an HTTP date (IMF-fixdate), such as `Sun, 06 Nov 1994 08:49:37 GMT`.
fn format_http_date(Timestamp ts) -> Result<string, TimeError> {
    let s = format_rfc2822(ts)?;
    return s;
}

fn parse_rfc2822_text(string text, bool gmt_only) -> Result<Timestamp, TimeError> {
    let tb = to_bytes(text);
    let n = tb.len();
    let pair = parse_weekday_name(tb, 0, n)?;
    let wd = pair.a;
    let i = expect_lit(tb, pair.b, n, ", ")?;
    pair = parse_two_digits(tb, i, n)?;
    let day = pair.a;
    i = expect_byte(tb, pair.b, n, 32)?;
    pair = parse_month_name(tb, i, n)?;
    let month = pair.a;
    i = expect_byte(tb, pair.b, n, 32)?;
    pair = parse_year(tb, i, n)?;
    let year = pair.a;
    i = expect_byte(tb, pair.b, n, 32)?;
    pair = parse_two_digits(tb, i, n)?;
    let hour = pair.a;
    i = expect_byte(tb, pair.b, n, 58)?;
    pair = parse_two_digits(tb, i, n)?;
    let minute = pair.a;
    i = expect_byte(tb, pair.b, n, 58)?;
    pair = parse_two_digits(tb, i, n)?;
    let second = pair.a;
    i = expect_byte(tb, pair.b, n, 32)?;
    let offset_min = 0;
    if bytes_eq_at(tb, i, n, "GMT") {
        i = i + 3;
    } else {
        if gmt_only == false && bytes_eq_at(tb, i, n, "UT") {
            i = i + 2;
        } else {
            if gmt_only {
                raise TimeError::ParseError;
            }
            if i >= n {
                raise TimeError::ParseError;
            }
            let z = tb[i] as int;
            if z != 43 && z != 45 {
                raise TimeError::ParseError;
            }
            let sign = 1;
            if z == 45 {
                sign = -1;
            }
            pair = parse_hhmm(tb, i + 1, n, false)?;
            offset_min = sign * pair.a;
            i = pair.b;
        }
    }
    if i != n {
        raise TimeError::ParseError;
    }
    if weekday_sun0(year, month, day) != wd {
        raise TimeError::ParseError;
    }
    let ts = timestamp_from_hms(year, month, day, hour, minute, second, 0)?;
    let out = apply_offset_minutes(ts, offset_min)?;
    return out;
}

/// Parse an RFC 2822 date, such as `Mon, 15 Jan 2024 12:30:00 -0500`.
///
/// The layout is `Www, DD Mon YYYY HH:MM:SS ZONE` with English three-letter
/// names; the zone is `GMT`, `UT` or `±HHMM`. A weekday that does not match the
/// date, or any other mismatch, is `TimeError::ParseError`.
///
/// # Examples
///
/// ```
/// use time::{parse_rfc2822, parse_rfc3339, Timestamp};
/// # use tests::assert;
/// let a = parse_rfc2822("Mon, 15 Jan 2024 12:30:00 -0500").map(fn (Timestamp t) => t.secs()).unwrap_or(0);
/// let b = parse_rfc3339("2024-01-15T17:30:00Z").map(fn (Timestamp t) => t.secs()).unwrap_or(1);
/// assert!(a == b);
/// ```
fn parse_rfc2822(string text) -> Result<Timestamp, TimeError> {
    let ts = parse_rfc2822_text(text, false)?;
    return ts;
}

/// Parse an HTTP date (IMF-fixdate), such as `Sun, 06 Nov 1994 08:49:37 GMT`.
///
/// Like `parse_rfc2822`, but the zone must be `GMT`.
///
/// # Examples
///
/// ```
/// use time::{parse_http_date};
/// # use tests::assert;
/// assert!(parse_http_date("Sun, 06 Nov 1994 08:49:37 GMT").is_ok());
/// assert!(parse_http_date("Sun, 06 Nov 1994 08:49:37 -0500").is_err());
/// ```
fn parse_http_date(string text) -> Result<Timestamp, TimeError> {
    let ts = parse_rfc2822_text(text, true)?;
    return ts;
}

impl Timestamp {
    /// Whole seconds since the epoch, rounded toward negative infinity.
    pub fn secs() -> int {
        return self.secs;
    }

    /// Whole milliseconds since the epoch, rounded toward negative infinity.
    pub fn millis() -> int {
        return self.millis;
    }

    /// Whole microseconds since the epoch, rounded toward negative infinity.
    pub fn micros() -> int {
        return self.micros;
    }

    /// Nanoseconds since the epoch.
    pub fn nanos() -> int {
        return self.nanos;
    }
}

impl Period {
    /// The `years` field.
    pub fn years() -> int {
        return self.years;
    }

    /// The `months` field.
    pub fn months() -> int {
        return self.months;
    }

    /// The `days` field.
    pub fn days() -> int {
        return self.days;
    }

    /// The `hours` field.
    pub fn hours() -> int {
        return self.hours;
    }

    /// The `minutes` field.
    pub fn minutes() -> int {
        return self.minutes;
    }

    /// The `secs` field.
    pub fn secs() -> int {
        return self.secs;
    }

    /// The `millis` field.
    pub fn millis() -> int {
        return self.millis;
    }

    /// The `micros` field.
    pub fn micros() -> int {
        return self.micros;
    }

    /// The `nanos` field.
    pub fn nanos() -> int {
        return self.nanos;
    }
}

impl Instant {
    /// Nanoseconds since this reading was taken (never negative).
    ///
    /// Returns `TimeError::InvalidInput` after `drop`.
    pub fn elapsed_nanos() -> Result<int, TimeError> {
        if self.live == 0 {
            raise TimeError::InvalidInput;
        }
        let now = mono_nanos();
        if now < self.snapshot {
            return 0;
        }
        return now - self.snapshot;
    }

    /// Whole milliseconds since this reading was taken.
    ///
    /// Returns `TimeError::InvalidInput` after `drop`.
    pub fn elapsed_millis() -> Result<int, TimeError> {
        let ns = self.elapsed_nanos()?;
        return ns / NS_PER_MS;
    }

    /// Whether this `Instant` can still be read, that is, `drop` has not been called.
    pub fn is_live() -> bool {
        return self.live != 0;
    }

    /// Mark this `Instant` dead; later `elapsed_*` reads return `TimeError::InvalidInput`.
    ///
    /// Calling it again does nothing.
    ///
    /// # Examples
    ///
    /// ```
    /// use time::{instant_now};
    /// # use tests::assert;
    /// let start = instant_now();
    /// start.drop();
    /// assert!(!start.is_live());
    /// assert!(start.elapsed_nanos().is_err());
    /// ```
    fn drop() {
        self.live = 0;
    }
}
