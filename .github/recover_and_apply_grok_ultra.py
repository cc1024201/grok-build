#!/usr/bin/env python3
"""Recover a single missing Base64 character, validate, and execute the Ultra transformer."""
from __future__ import annotations

import base64
import binascii
import re
import zlib
from pathlib import Path

SOURCE = Path(__file__).with_name("apply_grok_ultra.py")
ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"


def validated_source(payload: str) -> str | None:
    try:
        raw = base64.b64decode(payload, validate=True)
        source = zlib.decompress(raw).decode("utf-8")
        compile(source, "apply_grok_ultra_decoded.py", "exec")
        return source
    except (binascii.Error, zlib.error, UnicodeDecodeError, SyntaxError):
        return None


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

exec(compile(source, "apply_grok_ultra_decoded.py", "exec"))
