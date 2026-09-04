# coil-time

Userland calendar and monotonic time for [coil](https://github.com/ardax-corp/coil-lang). Process clocks (`wall_nanos`, `mono_nanos`, `sleep_ms`) are HostInvoke via virtual `clock`. This package is calendar, Instant snapshots, and format/parse. There is no cdylib.

The sixteen names in `src/time.hy` are `timestamp`, `sleep_ms`, `instant_now`, `elapsed_nanos`, `elapsed_millis`, `period`, `add`, `sub`, `period_add`, `period_sub`, `date`, `date_from_period`, `date_from_epoch_period`, `epoch`, `format`, and `parse`. Instant adds `drop` so a snapshot can be marked dead. Elapsed after drop is `TimeError::InvalidInput`.

RFC presets are named helpers (`format_rfc3339` / `parse_rfc3339`, `format_iso8601` / `parse_iso8601`, `format_iso8601_date` / `parse_iso8601_date`, `format_rfc2822` / `parse_rfc2822`, `format_http_date` / `parse_http_date`). `ISO8601_DATE` (`%Y-%m-%d`) and `ISO8601` (`%Y-%m-%dT%H:%M:%S`) are the pattern constants for `format` / `parse`.

## Layout

| Path | Role |
|------|------|
| `src/time.hy` | Package exports (`timestamp`, `period`, `Instant.drop`, …) |
| `coil.toml` | `[package] name = "time"` |

`use clock::{wall_nanos, mono_nanos, sleep_ms}` is the host edge. Instant is a Coil `int` mono snapshot plus a `live` flag. `elapsed_*` is `mono_now - start` in Coil.

Needs coil-lang archive **4.3** (HostInvoke ids 122–124).

## Build

```bash
make test     # coil tests (no native artifact)
```

Coil tests need `coil` on `PATH` (coil-lang default features are empty):

```bash
# sibling coil-lang (main, archive 4.3+)
cargo build -p coil
make test COIL=../coil-lang/target/debug/coil
```

Consume from a sibling checkout or a `coil.lock` pin (`rev` + `content_hash`). See [docs/consume.md](docs/consume.md).

Spool will own Coil-to-Coil deps once it exists. Until then there is no `spool add` and this repo has no tags. `{ git }` is the parseable git dep. `version` is optional schema, not a tag.

## License

MIT. See [LICENSE](LICENSE).
