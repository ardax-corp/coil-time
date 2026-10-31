# Consuming coil-time

This package is `time`. `use time::{timestamp, Instant}` resolves from this repo's `src/`. Process clocks are HostInvoke `clock` in coil-lang (archive 4.4+: `clock_wall_nanos` / `clock_mono_nanos` / `clock_sleep_ms`). Calendar, Instant, and format/parse live in Coil here. There is no `dload("time")` and no `libtime`. `use time` without this package's `src/` as a `--root` is a module-not-found error.

## Depend on it

With [spool](https://github.com/ardax-corp/spool):

```bash
spool add time --git https://github.com/ardax-corp/coil-time.git --rev <commit SHA>
```

This repo has no tags, so pin a commit with `--rev`. spool records the dep in `coil.toml`, writes `coil.lock` (`rev` + `content_hash`), links `.spool/deps/time`, and passes `--root` for it to `coil`. A sibling checkout also works as a path dep: `spool add time --path ../coil-time`.

Without spool, clone this repo next to your project and pass the root yourself. coil reads no `coil.toml` and no `coil.lock`. No `--allow-dload time`. No `--ffi-search-path`.

```bash
coil --root ../coil-time/src main.hy
```

Application code imports the Coil wrappers. It does not call `dload` or HostInvoke `clock_*` names itself.

```coil
use time::{timestamp, sleep_ms, instant_now, TimeError};

let ts = timestamp()?;
```

## Call it

```coil
use time::{instant_now, elapsed_nanos, Instant, TimeError};

let inst = instant_now();
let ns = elapsed_nanos(inst)?;
inst.drop();
```

`Instant` holds a process-monotonic nanos snapshot and a `live` flag. `Instant.drop` marks it dead (second drop is a no-op). `elapsed_nanos` / `elapsed_millis` on a dead Instant is `TimeError::InvalidInput`. Do not use the Instant after drop.

`Timestamp` is a field bag. `secs`, `millis`, `micros`, and `nanos` are the same instant at four scales. `Period` is a field bag of nine independent ints: `years`, `months`, `days`, `hours`, `minutes`, `secs`, `millis`, `micros`, `nanos`.

`TimeError` tags: `InvalidInput`, `Overflow`, `ParseError`, `Other`.

Shipped names in `src/time.hy`:

| Name | Notes |
|------|--------|
| `timestamp` | UTC now as `Timestamp` |
| `sleep_ms` | Negative millis is `InvalidInput` |
| `instant_now` | Mono snapshot Instant |
| `elapsed_nanos` / `elapsed_millis` | Elapsed since that Instant |
| `period` | Nine `int` fields |
| `add` / `sub` | Timestamp ± Period |
| `period_add` / `period_sub` | Field-wise, `Overflow` on i64 wrap |
| `date` | UTC midnight today as `Timestamp` |
| `date_from_period` / `date_from_epoch_period` | Calendar date; month/day 0 is `InvalidInput` |
| `epoch` | Zero nanos `Timestamp` |
| `format` / `parse` | `%Y` `%m` `%d` `%H` `%M` `%S` `%%` (tests' subset) |
| `ISO8601_DATE` / `ISO8601` | Documented `format` / `parse` patterns `%Y-%m-%d` / `%Y-%m-%dT%H:%M:%S` (ISO date / date-time body) |
| `format_rfc3339` / `parse_rfc3339` | UTC `Z`; parse also accepts `±HH:MM` and `.` fraction |
| `format_iso8601` / `parse_iso8601` | Same emit as RFC 3339; parse zone optional (UTC) or `±HH:MM` / `±HHMM` |
| `format_iso8601_date` / `parse_iso8601_date` | `YYYY-MM-DD` midnight UTC |
| `format_rfc2822` / `parse_rfc2822` | IMF-fixdate GMT emit; parse also accepts `UT` and `±HHMM` |
| `format_http_date` / `parse_http_date` | IMF-fixdate; parse requires `GMT` |
| `TimeError` | `InvalidInput`, `Overflow`, `ParseError`, `Other` |
| `Instant` | Coil snapshot. `drop` marks it dead |

Needs a coil-lang runtime with archive 4.4 (`clock` HostInvoke 121–123).
