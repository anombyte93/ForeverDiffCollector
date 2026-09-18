# Contributing

The easiest contribution is to [install the addon and upload a play session](README.md#help-by-playing). You don't need to code.

For bugs, include your addon version, the output of `/dump GetBuildInfo()`, what you did, what happened and what you expected. A cropped screenshot or exact Lua error helps. Don't post account folders, tokens or unreviewed personal data in an issue.

## Code and documentation

1. Fork this repo and clone your fork.
2. Change the files in `addon/ForeverDiffCollector/` or improve the docs.
3. Install Lua 5.1 or LuaJIT, and Python 3 for packaging. Run from the repo root:

   ```sh
   bash ops/test-addon.sh
   python3 ops/build-addon.py
   ```

4. For a gameplay change, install `dist/ForeverDiffCollector.zip` and describe the client build and steps you tested. The stub tests do not prove real-client compatibility.
5. Open a pull request describing the problem, your change and what you tested.

Keep changes small. Add a regression check in `addon/tests/run.lua` for behavioural fixes. Collection should remain event driven and bounded; keep personal data out and keep uploads manual. The game runtime is Lua 5.1-compatible.

## Data contract

`ForeverDiffCollectorDB.version` is **1**. Tables: `quests`, `npcs`, `objects`, `vendors`, `loot`, `kills`, `items`, `entrances`, plus `build` and `realm` metadata. A synthetic fixture lives in `addon/tests/fixtures/collector.lua`.

Adding optional fields can be backwards compatible. Renaming fields, changing keys or meanings, or removing fields requires coordination with the ForeverDiff importer and a versioned migration before release. The importer lives in the separate website project; changing this repo cannot deploy that importer.

## Releases (maintainers)

PRs changing the installed addon, package builder or release workflow must bump `## Version` in the TOC to a new `X.Y.Z` greater than the latest release. The PR check rejects reused versions. When the PR merges to `main`, GitHub Actions runs the tests, builds the ZIP, creates the version tag and publishes it as the latest release with a SHA-256 checksum. No manual tagging is needed. Documentation-only PRs do not trigger releases. Use the stable link below on the website and in messages:

https://github.com/anombyte93/ForeverDiffCollector/releases/latest/download/ForeverDiffCollector.zip

It follows the newest stable GitHub release without a website deployment. It does not automatically replace files on players' computers. The website's optional data-enriched ZIP is a separate deployment snapshot; its bundled code must be updated separately.
