# Consuming coil-time

This package is `time`. `use time::{timestamp, Instant}` resolves from this repo's `src/`. chrono and the Instant map live in `libtime.so` / `.dylib` / `time.dll`. `extern "time"` in `src/time.hy` already calls `dload("time")`. Put the built library on `[ffi] search_paths`.

`dload("time")` is not a stem skip. The consumer needs `[ffi] allow = ["time"]` and either a lock `sha256` or `trusted = true` on the time dep. Default `trusted` is `false`. Never `dload("c")`.

Coil-to-Coil deps will be spool-owned once a public `spool` CLI exists. Until [COI-219](https://linear.app/ardax/issue/COI-219) this repo has no git tags and there is no `spool add`. Pin `rev` + `content_hash` in `coil.lock` if you are not on a sibling checkout. Native libs stay on `[ffi] search_paths` until [COI-60](https://linear.app/ardax/issue/COI-60). Do not expect this package to write native pins.

Build `coil` with `--no-default-features` (no virtual `time` module) so `use time` resolves here.

## Sibling checkout

Clone this repo next to your project. In the consumer `coil.toml`:

```toml
[module]
roots = ["./src", "../coil-time/src"]

[ffi]
search_paths = ["../coil-time/native"]
allow = ["time"]

[dependencies]
time = { path = "../coil-time", trusted = true }
```

Build the native library from this package root:

```bash
make
```

`libtime.so` (or `.dylib` / `time.dll`) must sit on `[ffi] search_paths` so `dload("time")` resolves. `roots` must include this package's `src/` so `use time::{…}` resolves here. Application code imports the Coil wrappers. It does not call `dload` itself.

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
time = { git = "https://github.com/ardax-corp/coil-time.git", trusted = true }

[module]
roots = ["./src", "./.spool/deps/time/src"]

[ffi]
search_paths = ["./.spool/deps/time/native"]
allow = ["time"]
```

Allow without `trusted` or a lock `sha256` is denied. This repo does not ship `[[package.native]]` pins ([COI-60](https://linear.app/ardax/issue/COI-60)).

This repo has no tags until [COI-219](https://linear.app/ardax/issue/COI-219). The pin is `coil.lock` `rev` + `content_hash`. Omit `tag`. Use sibling checkout until spool materializes `.spool/deps`. The compiler does not read `coil.lock` and does not inject roots.

`coil.lock`:

```
# spool lockfile v1
[[package]]
name = 'time'
git = 'https://github.com/ardax-corp/coil-time.git'
rev = 'REPLACE_REV'
content_hash = 'REPLACE_TREE'
```

`rev` is the commit. `content_hash` is that commit's git tree (`git rev-parse 'HEAD^{tree}'`). Replace both when you move the pin. They are an example, not a release.

If you vendor that rev yourself, `.spool/deps/time` matches the later spool layout:

```bash
git clone https://github.com/ardax-corp/coil-time.git .spool/deps/time
git -C .spool/deps/time checkout --detach REPLACE_REV
test "$(git -C .spool/deps/time rev-parse 'HEAD^{tree}')" = REPLACE_TREE
make -C .spool/deps/time
```

`make` copies `libtime.so` (or `.dylib` / `time.dll`) into that `native/` dir. Leave it on `[ffi] search_paths`. Native libs stay on `[ffi] search_paths` until [COI-60](https://linear.app/ardax/issue/COI-60).

## Call it

```coil
use time::{instant_now, elapsed_nanos, Instant, TimeError};

let inst = instant_now();
let ns = elapsed_nanos(inst)?;
inst.drop();
```

`Instant.drop` removes the handle from the native map. A second Coil `drop` is a no-op. `elapsed_nanos` / `elapsed_millis` on a missing handle is `TimeError::InvalidInput`.

`Timestamp` fields (`secs`, `millis`, `micros`, `nanos`) are the same instant at four scales, matching the virtual wire. `Period` is nine independent fields (years … nanos).

`TimeError` tags: `InvalidInput`, `Overflow`, `ParseError`, `Other`.

Shipped names in `src/time.hy`:

| Name | Notes |
|------|--------|
| `timestamp` / `epoch` / `date` | UTC `Timestamp` |
| `sleep_ms` | Negative millis is `InvalidInput` |
| `instant_now` / `elapsed_nanos` / `elapsed_millis` | Opaque Instant handle |
| `period` | Nine `int` fields |
| `add` / `sub` | Timestamp ± Period |
| `period_add` / `period_sub` | Field-wise, `Overflow` on i64 wrap |
| `date_from_period` / `date_from_epoch_period` | Calendar date; month/day 0 is `InvalidInput` |
| `format` / `parse` | chrono format string |
| `TimeError` | `InvalidInput`, `Overflow`, `ParseError`, `Other` |
| `Instant` | Opaque native handle. Drop frees it |

Do not call `coil_time_*` from application code. Those symbols are the C ABI behind the wrappers.
