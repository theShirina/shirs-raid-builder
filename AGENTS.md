# AGENTS.md

## Project

Shir's Raid Builder is a standalone Microbot WoW 1.12 raid-planning addon. It targets Interface `11200` and Lua 5.0.3. It has two separate user workflows: Hire mode for building and executing paced hiring/setup plans, and Sort mode for capturing and arranging live raid layouts.

The addon can send commands that spend gold or whisper companions. Treat Preview, SavedVariables backups, pacing, reply handling, and explicit Execute/Sort actions as safety-critical behavior.

## Structure

- `addon/ShirsRaidBuilder/` — shipped addon files and TOC
- `addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua` — testable planning, parsing, validation, and command-building logic
- `addon/ShirsRaidBuilder/ShirsRaidBuilder_Abilities.lua` — maintained ability suggestions
- `addon/ShirsRaidBuilder/ShirsRaidBuilder.lua` — WoW UI, queues, event handling, Hire mode, and Sort mode
- `tests/test_core.lua` — Lua 5.0.3 core behavior tests
- `tests/test_mode_contract.lua` — source-level regression contract for mode separation and UI/queue invariants
- `tests/validate.py` — public-boundary, TOC, Lua syntax, behavior, and reproducible-package validation
- `scripts/build_release.py` — deterministic addon ZIP builder
- `.github/workflows/ci.yml` — GitHub Actions validation using a freshly built Lua 5.0.3
- `README.md` and `CHANGELOG.md` — public usage, limitations, and release history
- `dist/` — generated release archives; ignored by Git

## Commands

Run from the repository root with the exact Lua 5.0.3 interpreter and compiler:

```text
python tests/validate.py --lua <lua-5.0.3> --luac <luac-5.0.3>
python scripts/build_release.py
```

The validator also runs both Lua test files, compiles all shipped Lua files with `luac -p`, checks the public file boundary, builds the ZIP twice for reproducibility, and checks ZIP members and timestamps. CI performs the same validation after building Lua 5.0.3.

For targeted checks from `tests/`:

```text
<lua-5.0.3> test_core.lua
<lua-5.0.3> test_mode_contract.lua
```

## Versioning and release baseline

- Before changing a version, inspect the current public GitHub release/tag, the repository HEAD, `CHANGELOG.md`, `README.md`, `addon/ShirsRaidBuilder/README.txt`, and `addon/ShirsRaidBuilder/ShirsRaidBuilder.toc`.
- Treat the current public GitHub version as the release baseline. Keep the TOC, both READMEs, changelog heading, download filename/link, tag, and release ZIP consistent.
- Follow the project’s established numeric `major.minor` convention and the actual user-visible scope. A small bug fix within a newly introduced feature does **not** by itself warrant a new version; include it in that feature’s release unless it fixes a defect that existed in the previous public release or the project’s established history clearly requires a separate release.
- Do not bump a version for development-only test, documentation, packaging, or mechanical changes unless the public release convention requires it.
- Do not publish GitHub releases, tags, or Discord announcements without explicit authorization. Release-writing and publication preparation belong to the `release` profile.

## Working rules

- Preserve the separation between Hire mode and Sort mode. Hire execution must not silently start raid sorting; Sort mode must not send hiring commands.
- Preserve one-to-one normal-hire matching by owner/class/role and group-wide setup/deny expansion for all matching companions.
- Keep normal hire pacing at 7.5–8.5 seconds and preserve reply-aware whisper sequencing unless the task explicitly changes the protocol.
- Treat GRINFO and other Microbot responses as runtime data. Do not claim live coverage from static source inspection or synthetic tests.
- Use only WoW 1.12 and Lua 5.0.3-compatible syntax and APIs. Do not introduce Lua 5.1+ features or modern WoW APIs.
- Keep the public repository free of account data, SavedVariables, private client files, credentials, personal paths, and generated private snapshots.
- Keep the addon ZIP limited to the six files defined by `scripts/build_release.py`; do not place repository instructions, tests, or build scripts in the shipped addon folder.
- Do not change SavedVariables or client data merely to make a test pass.

## Verification boundaries

- Run the full validator with exact Lua 5.0.3 before handing off release work, plus targeted tests for the changed behavior when practical.
- Static tests and package validation do not prove live WoW/Microbot behavior. Stefán performs final live QA in the designated isolated test client; do not block implementation or claim that live QA was completed by an agent.
- When reporting a live issue, verify the invoked macro/button, loaded TOC/XML path, live function source, and active addon copy before attributing ownership.
- Package updates target the designated closed test-client installation by default, but never overwrite unrelated or custom installs.
- Do not commit generated archives, hashes, account data, client files, secrets, or unrelated changes.
