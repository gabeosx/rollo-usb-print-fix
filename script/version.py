#!/usr/bin/env python3
"""Validate the single release version and, optionally, its exact tag."""
from pathlib import Path
import re
import sys

version = (Path(__file__).resolve().parent.parent / "VERSION").read_text().strip()
number = r"(?:0|[1-9][0-9]*)"
identifier = r"(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
pattern = rf"{number}\.{number}\.{number}(?:-{identifier}(?:\.{identifier})*)?"
if not re.fullmatch(pattern, version):
    raise SystemExit("VERSION must contain MAJOR.MINOR.PATCH, optionally followed by a SemVer prerelease.")
if len(sys.argv) > 2 or (len(sys.argv) == 2 and sys.argv[1] != "v" + version):
    raise SystemExit("Release tag must exactly match v plus VERSION.")
print(version)
