# coil-time

Userland calendar and monotonic time for [coil](https://github.com/ardax-corp/coil-lang). Process clocks (`wall_nanos`, `mono_nanos`, `sleep_ms`) are HostInvoke via virtual `clock`. This package is calendar, Instant snapshots, and format/parse. There is no cdylib.

The sixteen names in `src/time.coil` are `timestamp`, `sleep_ms`, `instant_now`, `elapsed_nanos`, `elapsed_millis`, `period`, `add`, `sub`, `period_add`, `period_sub`, `date`, `date_from_period`, `date_from_epoch_period`, `epoch`, `format`, and `parse`. Instant adds `drop` so a snapshot can be marked dead. Elapsed after drop is `TimeError::InvalidInput`.

RFC presets are named helpers (`format_rfc3339` / `parse_rfc3339`, `format_iso8601` / `parse_iso8601`, `format_iso8601_date` / `parse_iso8601_date`, `format_rfc2822` / `parse_rfc2822`, `format_http_date` / `parse_http_date`). The documented `format` / `parse` patterns are `%Y-%m-%d` (ISO date, const `ISO8601_DATE`) and `%Y-%m-%dT%H:%M:%S` (date-time body, no zone, const `ISO8601`).

## Example

```coil
use io::sync::{println};
use time::{parse_rfc3339, format_rfc3339, format_http_date, add, period, TimeError};

// One month after `text`, as RFC 3339 and as an HTTP date.
fn next_month(string text) -> Result<string, TimeError> {
    let ts = parse_rfc3339(text)?;
    let later = add(ts, period(0, 1, 0, 0, 0, 0, 0, 0, 0)?)?;
    return format_rfc3339(later)? + " / " + format_http_date(later)?;
}

fn main() {
    let line = match next_month("2024-01-31T09:30:00+02:00") {
        Result::Ok(s) => s,
        Result::Err(_) => "bad date",
    };
    println(line)?;
}
```

```bash
coil --root ../coil-stdlib/src --root ../coil-time/src main.coil
# 2024-02-29T07:30:00Z / Thu, 29 Feb 2024 07:30:00 GMT
```

Jan 31 plus one month clamps to the last day of February. Every item in `src/time.coil` carries `///` docs with runnable examples (`coil test src` runs them).

## Layout

| Path | Role |
|------|------|
| `src/time.coil` | Package exports (`timestamp`, `period`, `Instant.drop`, …) |
| `coil.toml` | `[package] name = "time"` |

`use clock::{wall_nanos, mono_nanos, sleep_ms}` is the host edge. Instant is a Coil `int` mono snapshot plus a `live` flag. `elapsed_*` is `mono_now - start` in Coil.

Needs coil-lang archive **4.4** (HostInvoke ids 121–123).

## Build

```bash
make test     # coil tests (no native artifact)
```

Coil tests need `coil` on `PATH` (coil-lang default features are empty):

```bash
# sibling coil-lang (main, archive 4.4+)
cargo build -p coil
make test COIL=../coil-lang/target/debug/coil
```

Consume with `spool add time --git https://github.com/ardax-corp/coil-time.git --rev <commit SHA>` (no tags yet), or a sibling checkout plus `--root ../coil-time/src`. See [docs/consume.md](docs/consume.md).

## License

MIT. See [LICENSE](LICENSE).
