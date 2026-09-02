//! COI-258 pins: sixteen TIME_WIRING names/arities, Instant drop, TimeError wire.
//! Instant.drop is extra on Instant, not a 17th TIME_WIRING name.

use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;

use time::{
    coil_time_elapsed_millis, coil_time_elapsed_nanos, coil_time_instant_drop, coil_time_instant_now,
    coil_time_last_error,
};

const INVALID_INPUT: i64 = 0;
const OVERFLOW: i64 = 1;
const PARSE_ERROR: i64 = 2;
const OTHER: i64 = 3;
const RC_ERR: i64 = -1;
const RC_OK: i64 = 0;

/// Sixteen package names and arities (without a `time_` prefix).
const PACKAGE_TIME_WIRING: &[(&str, usize)] = &[
    ("timestamp", 0),
    ("sleep_ms", 1),
    ("instant_now", 0),
    ("elapsed_nanos", 1),
    ("elapsed_millis", 1),
    ("period", 9),
    ("add", 2),
    ("sub", 2),
    ("period_add", 2),
    ("period_sub", 2),
    ("date", 0),
    ("date_from_period", 1),
    ("date_from_epoch_period", 1),
    ("epoch", 0),
    ("format", 2),
    ("parse", 2),
];

const FFI_HELPERS: &[&str] = &[
    "err_ptr",
    "err_from",
    "copy_in",
    "copy_out",
    "take_timestamp",
    "take_period",
    "put_period",
];

fn repo_file(rel: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("..").join(rel)
}

fn read_repo(rel: &str) -> String {
    fs::read_to_string(repo_file(rel)).unwrap_or_else(|e| panic!("read {rel}: {e}"))
}

fn top_level_fns(src: &str) -> BTreeMap<String, usize> {
    let mut out = BTreeMap::new();
    for line in src.lines() {
        let Some(rest) = line.strip_prefix("fn ") else {
            continue;
        };
        let Some(open) = rest.find('(') else {
            continue;
        };
        let name = rest[..open].trim();
        if name.is_empty() {
            continue;
        }
        let after = &rest[open + 1..];
        let close = after
            .find(')')
            .unwrap_or_else(|| panic!("unclosed fn {name}"));
        let params = after[..close].trim();
        let arity = if params.is_empty() {
            0
        } else {
            params.split(',').count()
        };
        out.insert(name.to_string(), arity);
    }
    out
}

fn class_fields(src: &str, class: &str) -> Vec<String> {
    let header = format!("class {class} {{");
    let start = src
        .find(&header)
        .unwrap_or_else(|| panic!("missing {class}"));
    let body = &src[start + header.len()..];
    let end = body.find('}').unwrap_or_else(|| panic!("{class} body"));
    body[..end]
        .lines()
        .filter_map(|l| {
            let l = l.trim().trim_end_matches(',');
            if l.is_empty() {
                return None;
            }
            Some(l.split(':').next()?.trim().to_string())
        })
        .collect()
}

fn enum_variants(src: &str, name: &str) -> Vec<String> {
    let header = format!("enum {name} {{");
    let start = src.find(&header).unwrap_or_else(|| panic!("missing {name}"));
    let body = &src[start + header.len()..];
    let end = body.find('}').unwrap_or_else(|| panic!("{name} body"));
    body[..end]
        .lines()
        .filter_map(|l| {
            let l = l.trim().trim_end_matches(',');
            if l.is_empty() {
                return None;
            }
            Some(l.to_string())
        })
        .collect()
}

#[test]
fn sixteen_time_wiring_names_and_arities() {
    assert_eq!(PACKAGE_TIME_WIRING.len(), 16);
    let src = read_repo("src/time.hy");
    let fns = top_level_fns(&src);
    let mut wiring = BTreeMap::new();
    for (name, arity) in PACKAGE_TIME_WIRING {
        let got = fns
            .get(*name)
            .unwrap_or_else(|| panic!("missing TIME_WIRING name {name}"));
        assert_eq!(got, arity, "arity {name}");
        wiring.insert(*name, *arity);
    }
    assert_eq!(wiring.len(), 16);

    let extra: Vec<_> = fns
        .keys()
        .filter(|n| !wiring.contains_key(n.as_str()) && !FFI_HELPERS.contains(&n.as_str()))
        .cloned()
        .collect();
    assert!(
        extra.is_empty(),
        "17th TIME_WIRING-style name (or unknown top-level fn): {extra:?}"
    );
}

#[test]
fn instant_drop_is_not_a_seventeenth_wiring_name() {
    let src = read_repo("src/time.hy");
    let fns = top_level_fns(&src);
    assert!(!fns.contains_key("drop"), "drop must stay on Instant, not TIME_WIRING");
    assert!(
        src.contains("impl Instant") && src.contains("fn drop()"),
        "Instant.drop missing"
    );
    assert_eq!(PACKAGE_TIME_WIRING.len(), 16);
}

#[test]
fn timestamp_period_and_time_error_match_virtual_wire() {
    let src = read_repo("src/time.hy");
    assert_eq!(
        class_fields(&src, "Timestamp"),
        ["secs", "millis", "micros", "nanos"]
    );
    assert_eq!(
        class_fields(&src, "Period"),
        [
            "years", "months", "days", "hours", "minutes", "secs", "millis", "micros", "nanos"
        ]
    );
    assert_eq!(
        enum_variants(&src, "TimeError"),
        ["InvalidInput", "Overflow", "ParseError", "Other"]
    );
    assert_eq!(INVALID_INPUT, 0);
    assert_eq!(OVERFLOW, 1);
    assert_eq!(PARSE_ERROR, 2);
    assert_eq!(OTHER, 3);
}

#[test]
fn dload_time_is_allow_and_trusted_not_c() {
    let toml = read_repo("coil.toml");
    assert!(toml.contains("allow = [\"time\"]"), "missing [ffi] allow time");
    assert!(toml.contains("trusted = true"), "missing trusted = true");
    assert!(toml.contains("path = \".\""), "missing path = \".\" trusted dep");
    assert!(!toml.contains("allow = [\"c\"]"));
    let hy = read_repo("src/time.hy");
    assert!(hy.contains("extern \"time\""));
    assert!(!hy.contains("extern \"c\""));
    assert!(!hy.contains("dload(\"c\")"));
}

#[test]
fn instant_drop_frees_handle_second_drop_and_use_are_invalid_input() {
    let id = unsafe { coil_time_instant_now(std::ptr::null_mut()) };
    assert!(id > 0);
    let n = unsafe { coil_time_elapsed_nanos(id, std::ptr::null_mut()) };
    assert!(n >= 0, "elapsed before drop tag={}", coil_time_last_error());
    let rc = unsafe { coil_time_instant_drop(id, std::ptr::null_mut()) };
    assert_eq!(rc, RC_OK);
    let after = unsafe { coil_time_elapsed_nanos(id, std::ptr::null_mut()) };
    assert_eq!(after, RC_ERR);
    assert_eq!(coil_time_last_error(), INVALID_INPUT);
    let ms = unsafe { coil_time_elapsed_millis(id, std::ptr::null_mut()) };
    assert_eq!(ms, RC_ERR);
    assert_eq!(coil_time_last_error(), INVALID_INPUT);
    let again = unsafe { coil_time_instant_drop(id, std::ptr::null_mut()) };
    assert_eq!(again, RC_ERR);
    assert_eq!(coil_time_last_error(), INVALID_INPUT);
}

#[test]
fn missing_and_invalid_instant_handles_are_invalid_input() {
    for id in [0_i64, -1, 1_000_000_009] {
        let n = unsafe { coil_time_elapsed_nanos(id, std::ptr::null_mut()) };
        assert_eq!(n, RC_ERR, "elapsed_nanos id={id}");
        assert_eq!(coil_time_last_error(), INVALID_INPUT);
        let ms = unsafe { coil_time_elapsed_millis(id, std::ptr::null_mut()) };
        assert_eq!(ms, RC_ERR, "elapsed_millis id={id}");
        assert_eq!(coil_time_last_error(), INVALID_INPUT);
        let d = unsafe { coil_time_instant_drop(id, std::ptr::null_mut()) };
        assert_eq!(d, RC_ERR, "drop id={id}");
        assert_eq!(coil_time_last_error(), INVALID_INPUT);
    }
}
