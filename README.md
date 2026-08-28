# coil-time

Userland calendar and monotonic time for [coil](https://github.com/ardax-corp/coil-lang). chrono and a process-global Instant map live in a cdylib (`libtime.so` / `.dylib` / `.dll`) plus Coil wrappers. `use time::{…}` is this package.

Names match the sixteen TIME_WIRING hosts. Instant adds `drop` so a handle can be removed from the map. Missing or invalid handles are `TimeError::InvalidInput`.

## Layout

| Path | Role |
|------|------|
| `src/time.hy` | Package exports (`timestamp`, `period`, `Instant.drop`, …) |
| `native/` | Rust cdylib, C ABI `coil_time_*` |
| `coil.toml` | `[package] name = "time"`, `[ffi] allow = ["time"]`, `trusted = true` |

`extern "time"` / `dload("time")` resolves to `libtime.so` via `[ffi] search_paths = ["./native"]`. After [COI-266](https://linear.app/ardax/issue/COI-266), that stem needs `[ffi] allow` plus a lock `sha256` or `trusted = true`. This package's tests use allow plus `trusted = true`. Never `dload("c")`.

Instant state is an opaque `int` handle in the `.so`. `Instant.drop` calls `coil_time_instant_drop`.

## Build

```bash
make          # native/libtime.{so,dylib,dll}
make test     # cargo test in native/
```

Or:

```bash
cd native && cargo test && cargo build --release
# copy libtime.so / .dylib / time.dll into native/ so [ffi] search_paths finds it
```

Coil tests need a `coil` built **without** the default `time` feature so virtual `use time` does not shadow this package:

```bash
# sibling coil-lang
cargo build --no-default-features
../coil-lang/target/debug/coil test
```

Consume from a sibling checkout or a `coil.lock` pin (`rev` + `content_hash`). See [docs/consume.md](docs/consume.md).

Spool will own Coil-to-Coil deps once it exists ([COI-219](https://linear.app/ardax/issue/COI-219)). Until then there is no `spool add` and this repo has no tags. `{ git }` is the parseable git dep. Native libs stay on `[ffi] search_paths` until [COI-60](https://linear.app/ardax/issue/COI-60). This repo does not write native pins.

## License

MIT. See [LICENSE](LICENSE).
