# coil-time

Userland calendar and monotonic time for [coil](https://github.com/ardax-corp/coil-lang). chrono and a process-global Instant map live in a cdylib (`libtime.so` / `.dylib` / `.dll`) plus Coil wrappers. `use time::{…}` is this package.

The sixteen names in `src/time.hy` are `timestamp`, `sleep_ms`, `instant_now`, `elapsed_nanos`, `elapsed_millis`, `period`, `add`, `sub`, `period_add`, `period_sub`, `date`, `date_from_period`, `date_from_epoch_period`, `epoch`, `format`, and `parse`. Instant adds `drop` so a handle can be removed from the map. Missing or invalid handles are `TimeError::InvalidInput`.

## Layout

| Path | Role |
|------|------|
| `src/time.hy` | Package exports (`timestamp`, `period`, `Instant.drop`, …) |
| `native/` | Rust cdylib, C ABI `coil_time_*` |
| `coil.toml` | `[package] name = "time"`, `[ffi] allow = ["time"]`, `[ffi] search_paths` |

`extern "time"` / `dload("time")` resolves to `libtime.so` via `[ffi] search_paths = ["./native"]`. `--allow-dload time` is the typecheck grant. Runtime integrity is `coil.lock` `[[package.native]] sha256` of that file (`make coil-test`). Never `dload("c")`.

Instant state is an opaque `int` handle in the `.so`. `Instant.drop` calls `coil_time_instant_drop`. Same leftover analog as `Hasher.drop`.

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

Coil tests need a sibling `coil` on `PATH` (coil-lang default features are empty):

```bash
# sibling coil-lang
cargo build -p coil
make coil-test COIL=../coil-lang/target/debug/coil
```

Consume from a sibling checkout or a `coil.lock` pin (`rev` + `content_hash`). See [docs/consume.md](docs/consume.md).

Spool will own Coil-to-Coil deps once it exists. Until then there is no `spool add` and this repo has no tags. `{ git }` is the parseable git dep. `version` is optional schema, not a tag. Put the built native library on `[ffi] search_paths`.

## License

MIT. See [LICENSE](LICENSE).
