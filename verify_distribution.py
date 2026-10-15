#!/usr/bin/env python3
"""Inspect generated packages without installing or changing any queue."""
from pathlib import Path
import argparse
import hashlib
import subprocess
import tempfile
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--kind", choices=["unsigned-preview", "signed"], default="unsigned-preview")
args = parser.parse_args()
version = subprocess.check_output(["python3", str(root / "script/version.py")], text=True).strip()
packages = [root / "dist" / f"{prefix}Rollo-USB-Print-Fix-{version}-{args.kind}.pkg" for prefix in ["", "Remove-"]]
assert all(p.is_file() for p in packages), "Build the current install/remove pair first."
expected = {
    "Library/Application Support/Rollo USB Pacing/rollo-pacing": "rollo-pacing",
    "Library/Printers/RolloPacing/rastertorollo-paced": "rastertorollo-paced",
    "Library/Application Support/Rollo USB Pacing/README.md": None,
    "Library/Application Support/Rollo USB Pacing/ADMINISTRATORS.md": None,
    "Library/Application Support/Rollo USB Pacing/LICENSE": None,
}


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT)


with tempfile.TemporaryDirectory(prefix="rollo-package-audit-") as temporary:
    for index, package in enumerate(packages):
        expanded = Path(temporary) / str(index)
        run("/usr/sbin/pkgutil", "--expand-full", str(package), str(expanded))
        distribution = ET.parse(expanded / "Distribution").getroot()
        assert distribution.find("options").get("allow-external-scripts") in {"no", "false"}
        assert "system.run(" not in (expanded / "Distribution").read_text()
        component = next(expanded.glob("*-component.pkg"))
        payload = component / "Payload"
        files = {p.relative_to(payload).as_posix() for p in payload.rglob("*") if p.is_file()} if payload.exists() else set()
        is_remove = package.name.startswith("Remove-")
        assert files == (set() if is_remove else set(expected)), f"Unexpected payload: {files}"
        for relative, binary in expected.items():
            if not is_remove and binary:
                packaged = payload / relative
                assert hashlib.sha256(packaged.read_bytes()).digest() == hashlib.sha256((root / "build" / binary).read_bytes()).digest()
                run("/usr/bin/codesign", "--verify", "--strict", str(packaged))
        tool = component / "Scripts/rollo-pacing"
        assert hashlib.sha256(tool.read_bytes()).digest() == hashlib.sha256((root / "build/rollo-pacing").read_bytes()).digest()
        run("/usr/bin/codesign", "--verify", "--strict", str(tool))
        if not is_remove:
            bom = run("/usr/bin/lsbom", "-p", "fMUG", str(component / "Bom"))
            for line in bom.splitlines():
                fields = line.split("\t")
                assert fields[-2:] == ["root", "wheel"], line
                assert "w" not in fields[1].strip()[5:], line  # no group/other write
        print(f"PASS: {package.name}; exact allowed payload, matching signed binaries, no external Installer check program.")
app = root / "dist/Rollo USB Print Fix.app"
run("/usr/bin/codesign", "--verify", "--strict", str(app))
for name, package in [("Install", next(p for p in packages if not p.name.startswith("Remove-"))),
                      ("Remove", next(p for p in packages if p.name.startswith("Remove-")))]:
    assert (app / f"Contents/Resources/{name}.pkg").read_bytes() == package.read_bytes()
for binary in ["rollo-pacing", "rastertorollo-paced", "RolloPacingSetup"]:
    path = root / "build" / binary
    architectures = run("/usr/bin/lipo", "-archs", str(path)).split()
    assert set(architectures) == {"arm64", "x86_64"}
    strings = run("/usr/bin/strings", str(path))
    assert "/Users/" not in strings, "Machine path embedded in executable"
print(f"PASS: {args.kind} setup app signature/resource checks and all three universal binaries.")
