#!/usr/bin/env python3
"""Audit the public source tree, excluding generated build/dist artifacts."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent
excluded = {"build", "dist", ".git", "__pycache__"}
forbidden = {".ppd", ".prn", ".ras", ".pdf", ".heic", ".p12", ".key", ".mobileprovision", ".log"}
# Construct patterns to avoid flagging the audit script's own rules.
patterns = [r"/Users/" + r"[^/\s]+/", "X-Goog-" + "Signature", "X-Amz-" + "Credential",
            "-----BEGIN " + "(?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
            "shipping_label_" + "thermal_", "usb://[^\\s\"]+" + r"[?&]serial=\w+"]
issues = []
count = 0
for path in sorted(root.rglob("*")):
    relative = path.relative_to(root)
    if any(part in excluded for part in relative.parts):
        continue
    if path.is_symlink():
        issues.append(f"Symlink: {relative}")
        continue
    if not path.is_file():
        continue
    count += 1
    if path.suffix.lower() in forbidden:
        issues.append(f"Excluded artifact type: {relative}")
    try:
        content = path.read_text()
    except UnicodeDecodeError:
        issues.append(f"Unexpected binary in source: {relative}")
        continue
    if any(re.search(pattern, content) for pattern in patterns):
        issues.append(f"Review possible private data: {relative}")
if issues:
    raise SystemExit("\n".join(issues))
print(f"PASS: {count} source files; no forbidden artifact types, machine home paths, signed URLs, private-key markers or device serial URLs found.")
print("Pattern checks supplement manual review; they do not prove absence of all private or third-party material.")
