# Consuming coil-time

This package is `time`. `use time::{timestamp, Instant}` resolves from this repo's `src/`. chrono and the Instant map live in `libtime.so` / `.dylib` / `time.dll`. `extern "time"` in `src/time.hy` already calls `dload("time")`. Put the built library on `[ffi] search_paths`. `use time` without this package on `roots` is a module-not-found error.

This package's `coil.toml` does not use `[ffi] allow`. Typecheck grant is `--allow-dload time`. Runtime integrity is `coil.lock` `[[package.native]] sha256` plus `[dependencies] time = { path = ".", trusted = true }`. `[ffi] search_paths` locates the file. It is not a grant. Never `dload("c")`.

Coil-to-Coil deps will be spool-owned once a public `spool` CLI exists. Until then this repo has no git tags and there is no `spool add`. `{ git }` is the parseable git form. `version` is optional schema, not a tag. `rev` on the dep is stored only. Pin `rev` + `content_hash` in `coil.lock` if you are not on a sibling checkout. Put the built native library on `[ffi] search_paths`.

## Sibling checkout

This is the working path. Clone this repo next to your project. In the consumer `coil.toml`:

```toml
[module]
roots = ["./src", "../coil-time/src"]

[ffi]
search_paths = ["../coil-time/native"]

[dependencies]
time = { path = "../coil-time", trusted = true }
```

`[dependencies] time = { path = "../coil-time" }` is spool metadata. The compiler does not follow path deps for discovery. `roots` is what loads `src/time.hy`. Typecheck grant is `--allow-dload time`. `trusted = true` skips native `sha256` for stem `time`. Pin `coil.lock` `[[package.native]] sha256` of `libtime` if you do not set `trusted`.

Build the native library from this package root:

```bash
make
```

`libtime.so` (or `.dylib` / `time.dll`) must sit on `[ffi] search_paths` so `dload("time")` resolves. `roots` must include this package's `src/` so `use time::{…}` resolves here. Application code imports the Coil wrappers. It does not call `dload` itself. Pass `--allow-dload time` on typecheck and test.

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
```

This repo has no tags. The pin is `coil.lock` `rev` + `content_hash`. Omit `tag`. Use sibling checkout until spool materializes `.spool/deps`. The compiler does not read `coil.lock` and does not inject roots.

`coil.lock`:

```
# spool lockfile v1
[[package]]
name = 'time'
git = 'https://github.com/ardax-corp/coil-time.git'
rev = 'cf792aef88b587a111aec120e2b56e11ca4c3386'
content_hash = '4086f1fa08138ed6581a56b5a022e2eaa6786142'
```

`rev` is the commit. `content_hash` is that commit's git tree (`git rev-parse 'HEAD^{tree}'`). Replace both when you move the pin. The values above are `main` at `cf792ae`. They are an example, not a release.

If you vendor that rev yourself, `.spool/deps/time` matches the later spool layout:

```bash
git clone https://github.com/ardax-corp/coil-time.git .spool/deps/time
git -C .spool/deps/time checkout --detach cf792aef88b587a111aec120e2b56e11ca4c3386
test "$(git -C .spool/deps/time rev-parse 'HEAD^{tree}')" = 4086f1fa08138ed6581a56b5a022e2eaa6786142
make -C .spool/deps/time
```

`make` copies `libtime.so` (or `.dylib` / `time.dll`) into that `native/` dir. Leave it on `[ffi] search_paths`. Typecheck grant is `--allow-dload time`. Runtime integrity is `coil.lock` `[[package.native]] sha256` of that file, or `trusted = true` on the time dep.

## Call it

```coil
use time::{instant_now, elapsed_nanos, Instant, TimeError};

let inst = instant_now();
let ns = elapsed_nanos(inst)?;
inst.drop();
```

`Instant.drop` removes the handle from the native map. Same leftover analog as `Hasher.drop` in coil-crypto. A second Coil `drop` is a no-op. `elapsed_nanos` / `elapsed_millis` on a missing handle is `TimeError::InvalidInput`. Do not use the Instant after drop.

`Timestamp` is a field bag. `secs`, `millis`, `micros`, and `nanos` are the same instant at four scales. `Period` is a field bag of nine independent ints: `years`, `months`, `days`, `hours`, `minutes`, `secs`, `millis`, `micros`, `nanos`.

`TimeError` tags: `InvalidInput`, `Overflow`, `ParseError`, `Other`.

Shipped names in `src/time.hy`:

| Name | Notes |
|------|--------|
| `timestamp` | UTC now as `Timestamp` |
| `sleep_ms` | Negative millis is `InvalidInput` |
| `instant_now` | Opaque Instant handle |
| `elapsed_nanos` / `elapsed_millis` | Elapsed since that Instant |
| `period` | Nine `int` fields |
| `add` / `sub` | Timestamp ± Period |
| `period_add` / `period_sub` | Field-wise, `Overflow` on i64 wrap |
| `date` | UTC midnight today as `Timestamp` |
| `date_from_period` / `date_from_epoch_period` | Calendar date; month/day 0 is `InvalidInput` |
| `epoch` | Zero nanos `Timestamp` |
| `format` / `parse` | chrono format string |
| `TimeError` | `InvalidInput`, `Overflow`, `ParseError`, `Other` |
| `Instant` | Opaque native handle. `drop` frees it |

Do not call `coil_time_*` from application code. Those symbols are the C ABI behind the wrappers.
