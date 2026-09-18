#!/usr/bin/env python3
"""Build an installable, deterministic ZIP using only an explicit public file list."""
from pathlib import Path
import hashlib
import zipfile

root = Path(__file__).resolve().parents[1]
source = root / "addon" / "ForeverDiffCollector"
output = root / "dist" / "ForeverDiffCollector.zip"
output.parent.mkdir(exist_ok=True)
files = {name: (source / name).read_bytes() for name in (
    "ForeverDiffCollector.toc", "ForeverDiffData.lua", "ForeverDiffCollector.lua",
)}
files["LICENSE"] = (root / "LICENSE").read_bytes()
files["README.md"] = (root / "README.md").read_bytes()
for line in files["ForeverDiffCollector.toc"].decode().splitlines():
    if line.strip().endswith(".lua") and not line.startswith("#"):
        assert line.strip() in files, f"Missing TOC file: {line}"
with zipfile.ZipFile(output, "w") as archive:
    for name, body in sorted(files.items()):
        info = zipfile.ZipInfo(f"ForeverDiffCollector/{name}", (1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        archive.writestr(info, body)
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None
sha = hashlib.sha256(output.read_bytes()).hexdigest()
(output.parent / "SHA256SUMS.txt").write_text(f"{sha}  {output.name}\n")
print(f"{output.name}: {len(files)} files, {output.stat().st_size} bytes, sha256 {sha}")
