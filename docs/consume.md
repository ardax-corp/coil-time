# Consuming coil-time

This package is `time`. `use time::{timestamp, Instant}` resolves from this repo's `src/`. Process clocks are HostInvoke `clock` in coil-lang (archive 4.3+: `clock_wall_nanos` / `clock_mono_nanos` / `clock_sleep_ms`). Calendar, Instant, and format/parse live in Coil here. There is no `dload("time")` and no `libtime`. `use time` without this package on `roots` is a module-not-found error.

Coil-to-Coil deps will be spool-owned once a public `spool` CLI exists. Until then this repo has no git tags and there is no `spool add`. `{ git }` is the parseable git form. `version` is optional schema, not a tag. `rev` on the dep is stored only. Pin `rev` + `content_hash` in `coil.lock` if you are not on a sibling checkout.

## Sibling checkout

This is the working path. Clone this repo next to your project. In the consumer `coil.toml`:

```toml
[module]
roots = ["./src", "../coil-time/src"]

[dependencies]
time = { path = "../coil-time" }
```

`[dependencies] time = { path = "../coil-time" }` is spool metadata. The compiler does not follow path deps for discovery. `roots` is what loads `src/time.hy`. No `--allow-dload time`. No `[ffi] search_paths`.

Then:

```coil
use time::{timestamp, sleep_ms, instant_now, TimeError};

let ts = timestamp()?;
```

## Git dep and coil.lock

`{ git }` is the parseable form. `version` is optional schema, not a tag. `rev` on the dep is stored only. There is no public `spool` CLI. Do not run `spool add`.

Parseable example:

```toml
[dependencies]
time = { git = "https://github.com/ardax-corp/coil-time.git" }

[module]
roots = ["./src", "./.spool/deps/time/src"]
```

This repo has no tags. The pin is `coil.lock` `rev` + `content_hash`. Omit `tag`. Use sibling checkout until spool materializes `.spool/deps`. The compiler does not read `coil.lock` and does not inject roots.

`coil.lock`:

```
# spool lockfile v1
[[package]]
name = 'time'
git = 'https://github.com/ardax-corp/coil-time.git'
rev = 'REPLACE_WITH_PINNED_REV'
content_hash = 'REPLACE_WITH_TREE'
```

`rev` is the commit. `content_hash` is that commit's git tree (`git rev-parse 'HEAD^{tree}'`). Replace both when you move the pin.

If you vendor that rev yourself, `.spool/deps/time` matches the later spool layout:

```bash
git clone https://github.com/ardax-corp/coil-time.git .spool/deps/time
git -C .spool/deps/time checkout --detach REPLACE_WITH_PINNED_REV
```

`roots` must include this package's `src/` so `use time::{…}` resolves here. Application code imports the Coil wrappers. It does not call `dload` or HostInvoke `clock_*` names itself.

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
| `TimeError` | `InvalidInput`, `Overflow`, `ParseError`, `Other` |
| `Instant` | Coil snapshot. `drop` marks it dead |

Needs a coil-lang runtime with archive 4.3 (`clock` HostInvoke 122–124).
