#!/usr/bin/env python3
"""Recover, execute, and normalize the one-shot Grok Ultra transformer."""
from __future__ import annotations

import base64
import binascii
import re
import zlib
from pathlib import Path

SOURCE = Path(__file__).with_name("apply_grok_ultra.py")
REPO = Path(__file__).resolve().parents[1]
ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"


def validated_source(payload: str) -> str | None:
    try:
        raw = base64.b64decode(payload, validate=True)
        source = zlib.decompress(raw).decode("utf-8")
        compile(source, "apply_grok_ultra_decoded.py", "exec")
        return source
    except (binascii.Error, zlib.error, UnicodeDecodeError, SyntaxError):
        return None


def replace_once(path: Path, pattern: str, replacement: str) -> None:
    text = path.read_text(encoding="utf-8")
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.DOTALL)
    if count != 1:
        raise SystemExit(f"expected exactly one normalization match in {path}: {pattern!r}")
    path.write_text(updated, encoding="utf-8")


text = SOURCE.read_text(encoding="utf-8")
match = re.search(r"b64decode\('([^']+)'\)", text)
if match is None:
    raise SystemExit("could not locate transformer payload")
payload = match.group(1)
source = validated_source(payload)

if source is None:
    recovered: tuple[int, str, str] | None = None
    for index in range(len(payload) + 1):
        prefix = payload[:index]
        suffix = payload[index:]
        for char in ALPHABET:
            candidate = prefix + char + suffix
            candidate_source = validated_source(candidate)
            if candidate_source is not None:
                recovered = (index, char, candidate_source)
                break
        if recovered is not None:
            break
    if recovered is None:
        raise SystemExit("unable to recover transformer payload by one-character insertion")
    index, char, source = recovered
    print(f"Recovered transformer payload at character {index} with {char!r}")

# Keep the transformer's helper functions isolated from this normalizer.
transform_globals = {
    "__name__": "__main__",
    "__file__": "apply_grok_ultra_decoded.py",
}
exec(compile(source, "apply_grok_ultra_decoded.py", "exec"), transform_globals)

# Ultra is a local execution profile, not provider-owned model metadata. Keep
# metadata parsing pure/reversible and reject a server-supplied Ultra tier.
types_path = REPO / "crates/codegen/xai-grok-sampling-types/src/types.rs"
replace_once(
    types_path,
    r"pub fn parse_reasoning_effort_meta\(\n.*?\n\}\n\npub fn reasoning_effort_meta_value",
    '''pub fn parse_reasoning_effort_meta(
    meta: Option<&serde_json::Map<String, serde_json::Value>>,
) -> Option<ReasoningEffort> {
    let raw = meta?.get(REASONING_EFFORT_META_KEY)?;
    let s = match raw.as_str() {
        Some(s) => s,
        None => {
            tracing::warn!(value = %raw, "meta.reasoningEffort: expected string, ignoring");
            return None;
        }
    };
    match s.parse::<ReasoningEffort>() {
        Ok(effort) if effort.is_ultra() => {
            tracing::warn!(
                value = %s,
                "meta.reasoningEffort: Ultra is a client execution profile, ignoring provider value"
            );
            None
        }
        Ok(effort) => Some(effort),
        Err(err) => {
            tracing::warn!(value = %s, error = %err, "meta.reasoningEffort: parse failed, ignoring");
            None
        }
    }
}

pub fn reasoning_effort_meta_value''',
)
replace_once(
    types_path,
    r"pub fn parse_reasoning_effort_options\(arr: &\[serde_json::Value\]\) -> Vec<ReasoningEffortOption> \{\n.*?\n\}\n\n/// Parse the per-model",
    '''pub fn parse_reasoning_effort_options(arr: &[serde_json::Value]) -> Vec<ReasoningEffortOption> {
    arr.iter()
        .filter_map(
            |el| match serde_json::from_value::<ReasoningEffortOption>(el.clone()) {
                Ok(opt) if opt.value.is_ultra() => {
                    tracing::warn!(
                        value = %el,
                        "reasoningEfforts: Ultra is client-owned; skipping provider entry"
                    );
                    None
                }
                Ok(opt) => Some(opt),
                Err(err) => {
                    tracing::warn!(value = %el, error = %err, "reasoningEfforts: skipping invalid entry");
                    None
                }
            },
        )
        .collect()
}

/// Parse the per-model''',
)

# The focused test now enforces the ownership boundary rather than mutating the
# generic provider parser to manufacture a client-only menu row.
ultra_test = REPO / "crates/codegen/xai-grok-sampling-types/tests/ultra.rs"
replace_once(
    ultra_test,
    r"#\[test\]\nfn model_effort_menu_prepends_ultra_without_changing_provider_default\(\) \{\n.*?\n\}\n",
    '''#[test]
fn provider_effort_metadata_remains_unmodified_by_client_ultra() {
    let values = [serde_json::json!("high"), serde_json::json!("low")];
    let options = xai_grok_sampling_types::parse_reasoning_effort_options(&values);
    assert_eq!(options.len(), 2);
    assert!(options.iter().all(|option| !option.value.is_ultra()));
}
''',
)

print("Normalized client-owned Ultra semantics")
