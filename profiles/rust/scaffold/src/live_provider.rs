//! Reference LIVE flag provider — a file-config [`FlagProvider`] that reflects
//! changes WITHOUT a restart (Rust profile).
//!
//! This is the reference implementation of the live slot in the `flags` seam: it
//! re-reads a flag file on every resolution, so rewriting the file flips behaviour
//! in the SAME running process (a live runtime flip, not the env floor's
//! restart-to-toggle). A SaaS provider (OpenFeature / Unleash / LaunchDarkly) is an
//! adopter-pluggable alternative implementing the same [`FlagProvider`] — swap it in
//! via `set_provider()` with no change to callers of `is_enabled()`.
//!
//! TRUST BOUNDARY: `path` is APP-CONFIGURED (an operator-controlled deploy
//! artifact), NOT end-user input. The file CONTENT is still treated as untrusted
//! (it can be corrupted/tampered), so resolution is fully fail-safe and
//! injection-safe:
//!
//!   - fail-safe: a missing / unreadable / oversized / DEEPLY-NESTED file, a
//!     malformed / non-object payload (array/scalar/null), a non-bool value, or a
//!     flag absent from the file all fall back to the registry default (OFF).
//!     Resolution never panics and never enables on ANY file content. The byte cap
//!     is enforced with `Read::take` (TOCTOU-safe: it bounds the bytes pulled into
//!     memory regardless of a racing rewrite), so a huge/tampered file can never be
//!     slurped. Nesting is bounded by an ITERATIVE, heap-stacked scanner with a
//!     hard depth cap ([`MAX_DEPTH`]) — there is no recursion to overflow, so a
//!     deeply-nested tampered file cannot turn "flip a flag" into "crash the
//!     resolver" (the DoS class the Python Slice-2 review caught).
//!   - no injection: [`FORBIDDEN_KEYS`] (`__proto__`/`constructor`/`prototype` and
//!     dunder-ish keys) are rejected outright; only the SPECIFIC flag key is read —
//!     the parsed data is never spread/merged into anything.
//!   - strict coercion: only the JSON boolean `true` enables (a `"true"` string,
//!     `1`, etc. stay OFF — mirrors the env floor's strict `== "true"`).
//!
//! This scanner is deliberately minimal (it extracts top-level `"key": bool` pairs,
//! not a general value tree) and std-only — no JSON dependency, and no hand-rolled
//! recursive parser.
//!
//! PERFORMANCE CAVEAT: a SYNCHRONOUS file read on EVERY `is_enabled` call. Fine for
//! a kill-switch and for the shipped default (the env floor does no FS read at all),
//! but a profile/adopter wiring this onto a HOT request path should add an
//! mtime-gated cache.

use std::fs::File;
use std::io::Read;

use crate::flags::{registry_default, FlagProvider};

/// Byte cap on the flag file (1 MiB). A flag file is tiny (a handful of booleans);
/// 1 MiB is very generous. The cap bounds memory so an oversized/tampered file can
/// never be slurped in.
const MAX_FILE_BYTES: u64 = 1 << 20;

/// Hard nesting cap for the scanner. A flag file is flat; anything deeper is
/// rejected outright, so a deeply-nested tampered file is bounded work.
const MAX_DEPTH: usize = 32;

/// Names that must never be resolved from file data (builtin-shadowing /
/// prototype-pollution vectors).
const FORBIDDEN_KEYS: &[&str] = &["__proto__", "constructor", "prototype"];

/// A file-config provider that re-reads `path` per `is_enabled` call (the live
/// flip). Content is untrusted.
pub struct FileConfigProvider {
    path: String,
}

impl FileConfigProvider {
    /// Returns a provider whose `is_enabled` re-reads `path` per call, so rewriting
    /// the file flips behaviour with no restart.
    pub fn new(path: impl Into<String>) -> Self {
        Self { path: path.into() }
    }
}

impl FlagProvider for FileConfigProvider {
    fn is_enabled(&self, name: &str) -> bool {
        let fallback = registry_default(name);

        // Reject dunder-ish / pollution keys outright — never resolved from file data.
        if is_forbidden(name) {
            return fallback;
        }

        let data = match read_capped(&self.path) {
            Some(data) => data,
            None => return fallback,
        };

        // Only a literal top-level `"name": true`/`false` yields a value; a missing
        // key, a non-bool value, a non-object payload, malformed JSON, or too-deep
        // nesting all resolve to None -> the registry default (OFF).
        match top_level_bool(&data, name) {
            Some(value) => value,
            None => fallback,
        }
    }
}

/// True if `name` is a forbidden (dunder-ish / pollution) key.
fn is_forbidden(name: &str) -> bool {
    FORBIDDEN_KEYS.contains(&name) || (name.starts_with("__") && name.ends_with("__"))
}

/// Opens `path` and reads at most `MAX_FILE_BYTES`, rejecting anything larger. The
/// `take(MAX_FILE_BYTES + 1)` bound is TOCTOU-safe — it caps the bytes pulled into
/// memory regardless of a racing rewrite. Returns `None` on any error or oversize
/// (the caller treats that as fail-safe OFF).
fn read_capped(path: &str) -> Option<Vec<u8>> {
    let file = File::open(path).ok()?;
    let mut buf = Vec::new();
    file.take(MAX_FILE_BYTES + 1).read_to_end(&mut buf).ok()?;
    if buf.len() as u64 > MAX_FILE_BYTES {
        return None;
    }
    Some(buf)
}

// --- Minimal bounded JSON-ish scanner (std-only, iterative, non-panicking) ---

/// One lexical token. Numbers collapse to `Num` and strings keep their decoded
/// value (only keys are compared, so value strings are `Other` at parse time).
enum Token {
    ObjOpen,
    ObjClose,
    ArrOpen,
    ArrClose,
    Colon,
    Comma,
    Str(String),
    True,
    False,
    Null,
    Num,
}

/// Classification of a member's value — only booleans carry a flag decision.
enum ValueKind {
    BoolTrue,
    BoolFalse,
    Other,
}

/// Resolves the top-level key `name` to `Some(true)`/`Some(false)` when it maps to
/// a literal JSON boolean; `None` when the key is absent, non-bool, or the document
/// is not a single well-formed object (malformed / non-object / too deeply nested).
/// Fully iterative and non-panicking.
fn top_level_bool(data: &[u8], name: &str) -> Option<bool> {
    let tokens = tokenize(data)?;
    parse_object(&tokens, name)
}

/// Lexes `data` into tokens. Returns `None` on any invalid token (fail-safe).
fn tokenize(data: &[u8]) -> Option<Vec<Token>> {
    let mut tokens = Vec::new();
    let mut i = 0;
    while i < data.len() {
        let byte = data[i];
        match byte {
            b' ' | b'\t' | b'\n' | b'\r' => i += 1,
            b'{' => {
                tokens.push(Token::ObjOpen);
                i += 1;
            }
            b'}' => {
                tokens.push(Token::ObjClose);
                i += 1;
            }
            b'[' => {
                tokens.push(Token::ArrOpen);
                i += 1;
            }
            b']' => {
                tokens.push(Token::ArrClose);
                i += 1;
            }
            b':' => {
                tokens.push(Token::Colon);
                i += 1;
            }
            b',' => {
                tokens.push(Token::Comma);
                i += 1;
            }
            b'"' => {
                let (value, next) = lex_string(data, i)?;
                tokens.push(Token::Str(value));
                i = next;
            }
            b't' => {
                i = expect_literal(data, i, b"true")?;
                tokens.push(Token::True);
            }
            b'f' => {
                i = expect_literal(data, i, b"false")?;
                tokens.push(Token::False);
            }
            b'n' => {
                i = expect_literal(data, i, b"null")?;
                tokens.push(Token::Null);
            }
            b'-' | b'0'..=b'9' => {
                i = lex_number(data, i);
                tokens.push(Token::Num);
            }
            _ => return None, // any other byte is invalid
        }
    }
    Some(tokens)
}

/// Matches `literal` starting at `i`; returns the index past it, or `None`.
fn expect_literal(data: &[u8], i: usize, literal: &[u8]) -> Option<usize> {
    let end = i + literal.len();
    if end <= data.len() && &data[i..end] == literal {
        Some(end)
    } else {
        None
    }
}

/// Consumes a JSON number starting at `i` (leniently — value is unused) and returns
/// the index past it.
fn lex_number(data: &[u8], i: usize) -> usize {
    let mut j = i;
    while j < data.len() {
        match data[j] {
            b'0'..=b'9' | b'-' | b'+' | b'.' | b'e' | b'E' => j += 1,
            _ => break,
        }
    }
    j
}

/// Lexes a JSON string starting at the opening quote at `i`. Returns the decoded
/// value and the index past the closing quote, or `None` on an unterminated /
/// invalid-escape string. Non-panicking.
fn lex_string(data: &[u8], i: usize) -> Option<(String, usize)> {
    let mut out: Vec<u8> = Vec::new();
    let mut j = i + 1; // skip opening quote
    while j < data.len() {
        match data[j] {
            b'"' => return Some((String::from_utf8(out).ok()?, j + 1)),
            b'\\' => {
                j += 1;
                let escape = *data.get(j)?;
                match escape {
                    b'"' => out.push(b'"'),
                    b'\\' => out.push(b'\\'),
                    b'/' => out.push(b'/'),
                    b'b' => out.push(0x08),
                    b'f' => out.push(0x0C),
                    b'n' => out.push(b'\n'),
                    b'r' => out.push(b'\r'),
                    b't' => out.push(b'\t'),
                    b'u' => {
                        let end = j + 5;
                        if end > data.len() {
                            return None;
                        }
                        let hex = std::str::from_utf8(&data[j + 1..end]).ok()?;
                        let code = u32::from_str_radix(hex, 16).ok()?;
                        let ch = char::from_u32(code)?; // lone surrogate -> None (fail-safe)
                        let mut buf = [0u8; 4];
                        out.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
                        j += 4;
                    }
                    _ => return None,
                }
                j += 1;
            }
            other => {
                out.push(other);
                j += 1;
            }
        }
    }
    None // unterminated
}

/// Parses the token stream as a single JSON object and extracts the value of the
/// top-level key `name`. Returns `None` for a non-object root, a malformed member
/// list, or trailing tokens after the root object.
fn parse_object(tokens: &[Token], name: &str) -> Option<bool> {
    match tokens.first()? {
        Token::ObjOpen => {}
        _ => return None, // non-object payload
    }
    let mut i = 1;
    let mut result: Option<bool> = None;

    // Empty object `{}` (optionally with trailing garbage): no members, so the
    // target key is absent -> None -> registry default (OFF).
    if let Some(Token::ObjClose) = tokens.get(i) {
        return None;
    }

    loop {
        // key
        let key = match tokens.get(i)? {
            Token::Str(value) => value.as_str(),
            _ => return None,
        };
        i += 1;
        // colon
        match tokens.get(i)? {
            Token::Colon => i += 1,
            _ => return None,
        }
        // value
        let (kind, next) = parse_value(tokens, i)?;
        i = next;
        if key == name {
            result = match kind {
                ValueKind::BoolTrue => Some(true),
                ValueKind::BoolFalse => Some(false),
                ValueKind::Other => None, // present but non-bool -> registry default
            };
        }
        // separator
        match tokens.get(i)? {
            Token::Comma => i += 1,
            Token::ObjClose => {
                i += 1;
                break;
            }
            _ => return None,
        }
    }

    // Reject trailing tokens after the root object (malformed).
    if i != tokens.len() {
        return None;
    }
    result
}

/// Classifies a value token starting at `i` and returns the index past the value.
/// Nested containers are skipped (balanced, depth-capped) and classified `Other`.
fn parse_value(tokens: &[Token], i: usize) -> Option<(ValueKind, usize)> {
    match tokens.get(i)? {
        Token::True => Some((ValueKind::BoolTrue, i + 1)),
        Token::False => Some((ValueKind::BoolFalse, i + 1)),
        Token::Null | Token::Num | Token::Str(_) => Some((ValueKind::Other, i + 1)),
        Token::ObjOpen | Token::ArrOpen => Some((ValueKind::Other, skip_container(tokens, i)?)),
        _ => None, // a close/colon/comma where a value is expected -> malformed
    }
}

/// Skips a balanced container starting at `start` using an iterative heap stack of
/// expected closers, capped at [`MAX_DEPTH`]. Returns the index past the matching
/// close, or `None` on a mismatch or over-deep nesting. No recursion — cannot
/// overflow the stack.
fn skip_container(tokens: &[Token], start: usize) -> Option<usize> {
    let mut stack: Vec<bool> = Vec::new(); // true = expect ObjClose, false = expect ArrClose
    let mut i = start;
    loop {
        match tokens.get(i)? {
            Token::ObjOpen => {
                stack.push(true);
                if stack.len() > MAX_DEPTH {
                    return None;
                }
            }
            Token::ArrOpen => {
                stack.push(false);
                if stack.len() > MAX_DEPTH {
                    return None;
                }
            }
            Token::ObjClose => {
                if stack.pop() != Some(true) {
                    return None;
                }
                if stack.is_empty() {
                    return Some(i + 1);
                }
            }
            Token::ArrClose => {
                if stack.pop() != Some(false) {
                    return None;
                }
                if stack.is_empty() {
                    return Some(i + 1);
                }
            }
            _ => {} // scalars / separators inside a non-target container are ignored
        }
        i += 1;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static COUNTER: AtomicU64 = AtomicU64::new(0);

    /// A unique temp path per test to avoid cross-test collisions.
    fn temp_path() -> std::path::PathBuf {
        let unique = COUNTER.fetch_add(1, Ordering::Relaxed);
        std::env::temp_dir().join(format!(
            "sp_rust_flags_{}_{}.json",
            std::process::id(),
            unique
        ))
    }

    fn resolve(contents: &str, name: &str) -> bool {
        let path = temp_path();
        std::fs::write(&path, contents).unwrap();
        let provider = FileConfigProvider::new(path.to_string_lossy().to_string());
        let result = provider.is_enabled(name);
        let _ = std::fs::remove_file(&path);
        result
    }

    #[test]
    fn literal_true_enables() {
        assert!(resolve(r#"{"new_greeting": true}"#, "new_greeting"));
    }

    #[test]
    fn literal_false_is_off() {
        assert!(!resolve(r#"{"new_greeting": false}"#, "new_greeting"));
    }

    #[test]
    fn string_true_is_off() {
        // strict coercion — a "true" string never enables
        assert!(!resolve(r#"{"new_greeting": "true"}"#, "new_greeting"));
    }

    #[test]
    fn number_one_is_off() {
        assert!(!resolve(r#"{"new_greeting": 1}"#, "new_greeting"));
    }

    #[test]
    fn missing_key_is_off() {
        assert!(!resolve(r#"{"other": true}"#, "new_greeting"));
    }

    #[test]
    fn nested_matching_key_does_not_enable() {
        // a matching key NESTED inside another object is not a top-level flag
        assert!(!resolve(
            r#"{"outer": {"new_greeting": true}}"#,
            "new_greeting"
        ));
    }

    #[test]
    fn non_object_payloads_are_off() {
        assert!(!resolve("[1, 2, 3]", "new_greeting"));
        assert!(!resolve("42", "new_greeting"));
        assert!(!resolve(r#""new_greeting""#, "new_greeting"));
        assert!(!resolve("null", "new_greeting"));
        assert!(!resolve("true", "new_greeting"));
    }

    #[test]
    fn malformed_json_is_off() {
        assert!(!resolve(r#"{"new_greeting": tru}"#, "new_greeting"));
        assert!(!resolve(r#"{"new_greeting": true"#, "new_greeting")); // unterminated object
        assert!(!resolve(r#"{"new_greeting" true}"#, "new_greeting")); // missing colon
        assert!(!resolve("{", "new_greeting"));
        assert!(!resolve("", "new_greeting"));
    }

    #[test]
    fn trailing_garbage_is_off() {
        // real JSON rejects trailing tokens; the whole doc is untrusted -> OFF
        assert!(!resolve(
            r#"{"new_greeting": true} garbage"#,
            "new_greeting"
        ));
    }

    #[test]
    fn tampered_true_beside_broken_sibling_is_off() {
        // a mismatched-bracket sibling makes the whole doc malformed -> the
        // present true must NOT leak through
        assert!(!resolve(
            r#"{"new_greeting": true, "x": {]}"#,
            "new_greeting"
        ));
    }

    #[test]
    fn forbidden_keys_never_resolve() {
        assert!(!resolve(r#"{"__proto__": true}"#, "__proto__"));
        assert!(!resolve(r#"{"constructor": true}"#, "constructor"));
        assert!(!resolve(r#"{"prototype": true}"#, "prototype"));
        assert!(!resolve(r#"{"__dunder__": true}"#, "__dunder__"));
    }

    #[test]
    fn deeply_nested_file_is_off_and_does_not_crash() {
        // a tamperer cannot turn "flip a flag" into "crash the resolver"
        let deep = format!(
            r#"{{"new_greeting": true, "x": {}{}}}"#,
            "[".repeat(1000),
            "]".repeat(1000)
        );
        assert!(!resolve(&deep, "new_greeting"));
    }

    #[test]
    fn oversized_file_is_off() {
        // a >1 MiB file is rejected by the byte cap even though it parses to true
        let mut contents = String::from(r#"{"new_greeting": true}"#);
        contents.push_str(&" ".repeat((MAX_FILE_BYTES as usize) + 16));
        assert!(!resolve(&contents, "new_greeting"));
    }

    #[test]
    fn missing_file_is_off() {
        let provider = FileConfigProvider::new("/no/such/flag/file.json".to_string());
        assert!(!provider.is_enabled("new_greeting"));
    }

    #[test]
    fn live_flip_without_restart() {
        let path = temp_path();
        let provider = FileConfigProvider::new(path.to_string_lossy().to_string());

        std::fs::write(&path, r#"{"new_greeting": false}"#).unwrap();
        assert!(!provider.is_enabled("new_greeting"));

        // rewrite the SAME file — the same provider instance observes the flip
        std::fs::write(&path, r#"{"new_greeting": true}"#).unwrap();
        assert!(provider.is_enabled("new_greeting"));

        std::fs::write(&path, r#"{"new_greeting": false}"#).unwrap();
        assert!(!provider.is_enabled("new_greeting"));

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn unicode_escape_key_is_handled() {
        // x == 'x'; the scanner decodes escapes without panicking
        assert!(resolve(r#"{"new_greeting": true}"#, "new_greeting"));
    }

    #[test]
    fn empty_object_is_off() {
        assert!(!resolve("{}", "new_greeting"));
        assert!(!resolve("   {  }   ", "new_greeting"));
    }
}
