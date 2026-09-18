#!/usr/bin/env python3
"""Reject release-affecting PRs that reuse a published version."""
import os
from pathlib import Path
import re
import subprocess

changed = subprocess.check_output([
    "git", "diff", "--name-only", os.environ["BASE_SHA"], os.environ["HEAD_SHA"],
], text=True).splitlines()
relevant = any(p.startswith("addon/ForeverDiffCollector/") or p in (
    "ops/build-addon.py", ".github/workflows/release.yml",
) for p in changed)
if relevant:
    toc = Path("addon/ForeverDiffCollector/ForeverDiffCollector.toc").read_text()
    version = re.search(r"^## Version: (.+)$", toc, re.M).group(1)
    assert re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version), "Use X.Y.Z"
    tags = subprocess.check_output(["git", "tag", "--list", "v*"], text=True).splitlines()
    published = [tuple(map(int, t[1:].split("."))) for t in tags
                 if re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", t)]
    # A preceding PR may have merged while its release job is still queued.
    # Compare the base commit too, so two PRs cannot reuse that unpublished version.
    base_toc = subprocess.check_output([
        "git", "show", os.environ["BASE_SHA"] + ":addon/ForeverDiffCollector/ForeverDiffCollector.toc",
    ], text=True)
    base_version = re.search(r"^## Version: (.+)$", base_toc, re.M).group(1)
    published.append(tuple(map(int, base_version.split("."))))
    assert tuple(map(int, version.split("."))) > max(published), (
        "Bump ## Version in ForeverDiffCollector.toc above the latest release. "
        "Merging this PR will publish that version automatically."
    )
    print("New release version:", version)
else:
    print("No release-affecting changes; no version bump needed.")
