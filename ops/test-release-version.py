#!/usr/bin/env python3
"""Exercise the PR version gate in isolated repositories, with no GitHub access."""
import os
from pathlib import Path
import subprocess
import tempfile

script = Path(__file__).with_name("check-release-version.py").resolve()

def scenario(base_version, head_version, *, docs_only=False, tag=None, passes):
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        def git(*args):
            return subprocess.check_output(["git", "-C", tmp, *args], text=True,
                                           stderr=subprocess.DEVNULL).strip()
        git("init", "-b", "main")
        git("config", "user.name", "Fixture")
        git("config", "user.email", "fixture@example.test")
        toc = root / "addon/ForeverDiffCollector/ForeverDiffCollector.toc"
        toc.parent.mkdir(parents=True)
        toc.write_text(f"## Version: {base_version}\n")
        git("add", "."); git("commit", "-m", "base")
        base = git("rev-parse", "HEAD")
        if tag:
            git("tag", tag)
        if docs_only:
            (root / "README.md").write_text("Documentation change\n")
        else:
            toc.write_text(f"## Version: {head_version}\n")
            toc.with_suffix(".lua").write_text("-- Runtime change\n")
        git("add", "."); git("commit", "-m", "proposed change")
        result = subprocess.run(["python3", str(script)], cwd=root, text=True,
                                capture_output=True, env={**os.environ, "BASE_SHA": base,
                                "HEAD_SHA": git("rev-parse", "HEAD")})
        assert (result.returncode == 0) == passes, result.stdout + result.stderr

scenario("1.0.0", "1.0.0", tag="v1.0.0", passes=False)
scenario("1.0.1", "1.0.1", tag="v1.0.0", passes=False)
scenario("1.0.1", "1.0.2", tag="v1.0.0", passes=True)
scenario("1.0.0", "1.0.0", docs_only=True, tag="v1.0.0", passes=True)
print("4 release-version regression cases passed")
