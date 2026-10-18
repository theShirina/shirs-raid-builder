from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "addon" / "ShirsRaidBuilder"
RELEASE_FILES = [
    "ShirsRaidBuilder_Core.lua",
    "ShirsRaidBuilder_Abilities.lua",
    "ShirsRaidBuilder.lua",
    "ShirsRaidBuilder.toc",
    "LICENSE",
    "README.txt",
]
PUBLIC_FILES = {
    "AGENTS.md",
    ".gitattributes",
    ".github/workflows/ci.yml",
    ".gitignore",
    "CHANGELOG.md",
    "LICENSE",
    "README.md",
    "addon/ShirsRaidBuilder/LICENSE",
    "addon/ShirsRaidBuilder/README.txt",
    "addon/ShirsRaidBuilder/ShirsRaidBuilder.lua",
    "addon/ShirsRaidBuilder/ShirsRaidBuilder.toc",
    "addon/ShirsRaidBuilder/ShirsRaidBuilder_Abilities.lua",
    "addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua",
    "scripts/build_release.py",
    "tests/test_core.lua",
    "tests/test_deny_batch.lua",
    "tests/test_individual_editor.lua",
    "tests/test_legacy_characters.lua",
    "tests/test_legacy_duplicates.lua",
    "tests/test_legacy_list.lua",
    "tests/test_preset_import.lua",
    "tests/test_peer.lua",
    "tests/test_peer_ui.lua",
    "tests/test_sync_ui.lua",
    "tests/test_raid_sync.lua",
    "tests/test_mcp_lockouts.lua",
    "tests/test_planning_characters.lua",
    "tests/test_handoff.lua",
    "tests/test_handoff_ui.lua",
    "tests/test_handoff_safety.lua",
    "tests/test_handoff_chat.lua",
    "tests/test_quiet_mode.lua",
    "tests/test_quick_hire.lua",
    "tests/test_quick_followup.lua",
    "tests/test_quick_final_choice.lua",
    "tests/test_planner_vanilla_ui.lua",
    "tests/test_random_hire.lua",
    "tests/test_random_runtime.lua",
    "tests/test_stop.lua",
    "tests/test_ui_integration.lua",
    "tests/test_planner.lua",
    "tests/test_planner_refinements.lua",
    "tests/test_planner_sources_compact.lua",
    "tests/test_planner_sources_wrap.lua",
    "tests/test_planner_selectors.lua",
    "tests/test_planner_composition_render.lua",
    "tests/test_planner_staged_groups.lua",
    "tests/test_planner_constraints.lua",
    "tests/test_planner_identities.lua",
    "tests/test_planner_human_tail.lua",
    "tests/test_planner_save_gold.lua",
    "tests/test_planner_quotes.lua",
    "tests/test_planner_linked_quotes.lua",
    "tests/test_planner_quote_safety.lua",
    "tests/test_planner_quote_curve.lua",
    "tests/test_planner_caster_block.lua",
    "tests/test_planner_estimates.lua",
    "tests/test_planner_race_defaults.lua",
    "tests/test_planner_auto_sync.lua",
    "tests/test_planner_draft_totals.lua",
    "tests/test_planner_tab_selection.lua",
    "tests/test_visible_plan_prices.lua",
    "tests/test_visible_price_ordinals.lua",
    "tests/test_visible_price_safety.lua",
    "tests/test_visible_native_sync.lua",
    "tests/test_planner_ultra.lua",
    "tests/test_planner_ultra_ui.lua",
    "tests/test_planner_wheel_dropdown.lua",
    "tests/test_pricing_bounds.lua",
    "tests/test_native_review.lua",
    "tests/test_ultra_priority.lua",
    "tests/test_ultra_global.lua",
    "tests/test_save_plan.lua",
    "tests/test_performance_transactions.lua",
    "tests/test_performance_quotes.lua",
    "tests/test_performance_pools.lua",
    "tests/test_price_persistence.lua",
    "tests/test_quote_rate.lua",
    "tests/test_hire_footer.lua",
    "tests/test_human_remove.lua",
    "tests/test_login_player.lua",
    "tests/test_board_plan_lifecycle.lua",
    "tests/test_planner_roster.lua",
    "tests/test_planner_priority.lua",
    "tests/test_planner_player.lua",
    "tests/test_planner_ui.lua",
    "tests/test_planner_execution.lua",
    "tests/test_run_authorization.lua",
    "tests/test_local_hire.lua",
    "tests/test_present_legacy.lua",
    "tests/test_normal_legacy.lua",
    "tests/test_account_sync.lua",
    "tests/test_plan_share.lua",
    "tests/test_plan_share_ui.lua",
    "tests/test_mode_contract.lua",
    "tests/validate.py",
}


def run(args: list[str], cwd: Path = ROOT, env: dict[str, str] | None = None) -> str:
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True, errors="replace", env=env)
    if result.returncode:
        detail = (result.stdout + "\n" + result.stderr).strip()
        raise AssertionError("command failed: " + " ".join(args) + ("\n" + detail if detail else ""))
    return result.stdout.strip()


def parse_toc(path: Path) -> tuple[dict[str, str], list[str]]:
    metadata: dict[str, str] = {}
    files: list[str] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("## ") and ":" in line:
            key, value = line[3:].split(":", 1)
            metadata[key.strip()] = value.strip()
        elif not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return metadata, files


def public_files() -> set[str]:
    ignored = {".git", "dist", "__pycache__"}
    found: set[str] = set()
    for path in ROOT.rglob("*"):
        if not path.is_file() or any(part in ignored for part in path.relative_to(ROOT).parts):
            continue
        if path.suffix in {".pyc", ".pyo"}:
            continue
        found.add(path.relative_to(ROOT).as_posix())
    return found


def validate_public_boundary() -> None:
    found = public_files()
    assert found == PUBLIC_FILES, "unexpected public file set: " + repr(sorted(found ^ PUBLIC_FILES))
    assert (ROOT / "LICENSE").read_bytes() == (ADDON / "LICENSE").read_bytes()
    text = "\n".join((ROOT / relative).read_text(encoding="utf-8", errors="replace") for relative in sorted(found))
    assert re.search(r"(?<![A-Za-z])[A-Z]:[\\/]", text) is None, "absolute Windows path found"
    assert re.search(r"[A-Za-z0-9._%+-]+@(gmail|hotmail|outlook)\.[A-Za-z]+", text, re.IGNORECASE) is None, "personal email found"
    assert ("STEFF" + "IPKH") not in text
    assert ("BEGIN " + "PRIVATE KEY") not in text
    for readme in (ROOT / "README.md", ADDON / "README.txt"):
        documentation = " ".join(readme.read_text(encoding="utf-8").replace("`", "").replace("**", "").split())
        assert "Opening /srb is display-only and does not start synchronization." in documentation, readme.name + ": missing display-only open contract"
        assert "Synchronization runs on login or when you click Refresh Synchronization." in documentation, readme.name + ": missing login/manual refresh contract"
        assert re.search(r"Opening /srb sends", documentation, re.IGNORECASE) is None, readme.name + ": stale open-sync claim"


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate Shir's Raid Builder")
    parser.add_argument("--lua", required=True)
    parser.add_argument("--luac", required=True)
    args = parser.parse_args()

    validate_public_boundary()

    toc = ADDON / "ShirsRaidBuilder.toc"
    metadata, runtime_files = parse_toc(toc)
    assert metadata.get("Interface") == "11200"
    version = metadata.get("Version", "")
    assert re.fullmatch(r"\d+\.\d+", version), "invalid TOC version: " + repr(version)
    assert metadata.get("SavedVariables") == "ShirsRaidBuilderDB"
    assert metadata.get("Author") == "Shirina"
    assert (ROOT / "CHANGELOG.md").read_text(encoding="utf-8").startswith("# Changelog\n\n## " + version + "\n")
    assert (ADDON / "README.txt").read_text(encoding="utf-8").startswith("Shir's Raid Builder " + version + "\n")
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    assert ("ShirsRaidBuilder-" + version + ".zip") in readme
    assert runtime_files == ["ShirsRaidBuilder_Core.lua", "ShirsRaidBuilder_Abilities.lua", "ShirsRaidBuilder.lua"]
    for relative in runtime_files:
        assert (ADDON / relative).is_file(), relative
        run([args.luac, "-p", str(ADDON / relative)])

    core_output = run([args.lua, str(ROOT / "tests" / "test_core.lua")], cwd=ROOT / "tests")
    assert "Shir's Raid Builder core tests: PASS" in core_output
    mode_output = run([args.lua, str(ROOT / "tests" / "test_mode_contract.lua")], cwd=ROOT / "tests")
    assert "Shir's Raid Builder mode contract tests: PASS" in mode_output
    individual_output = run([args.lua, str(ROOT / "tests" / "test_individual_editor.lua")], cwd=ROOT / "tests")
    assert "Shir's Raid Builder individual editor tests: PASS" in individual_output
    legacy_output = run([args.lua, str(ROOT / "tests" / "test_legacy_characters.lua")], cwd=ROOT / "tests")
    assert "Shir's Raid Builder legacy character tests: PASS" in legacy_output
    run([args.luac, "-p", str(ROOT / "tests" / "test_legacy_duplicates.lua")])
    duplicate_output = run([args.lua, str(ROOT / "tests" / "test_legacy_duplicates.lua")], cwd=ROOT / "tests")
    assert "Shir's Raid Builder legacy duplicate tests: PASS" in duplicate_output
    run([args.luac, "-p", str(ROOT / "tests" / "test_legacy_list.lua")])
    legacy_list_output = run([args.lua, str(ROOT / "tests" / "test_legacy_list.lua")], cwd=ROOT / "tests")
    assert "Shir's Raid Builder legacy list tests: PASS" in legacy_list_output
    run([args.luac, "-p", str(ROOT / "tests" / "test_preset_import.lua")])
    import_output = run([args.lua, str(ROOT / "tests" / "test_preset_import.lua")], cwd=ROOT / "tests")
    assert "Shir's Raid Builder preset import tests: PASS" in import_output

    output = run([args.lua, str(ROOT / "tests" / "test_mcp_lockouts.lua")], cwd=ROOT / "tests")
    assert "MCP lockout tests: PASS" in output
    for case, label in [("test_deny_batch.lua", "deny batch"), ("test_peer.lua", "peer"), ("test_peer_ui.lua", "peer UI"), ("test_sync_ui.lua", "sync UI"), ("test_raid_sync.lua", "raid sync"), ("test_account_sync.lua", "account sync"), ("test_plan_share.lua", "plan share"), ("test_plan_share_ui.lua", "plan share UI")]:
        run([args.luac, "-p", str(ROOT / "tests" / case)])
        output = run([args.lua, str(ROOT / "tests" / case)], cwd=ROOT / "tests")
        marker = "PASS raid sync:" if case == "test_raid_sync.lua" else "Shir's Raid Builder " + label + " tests: PASS"
        assert marker in output, case + " did not report success: " + output

    for case, label in [("test_planning_characters.lua", "planning character"), ("test_handoff.lua", "handoff core"), ("test_handoff_ui.lua", "handoff UI"), ("test_handoff_safety.lua", "handoff safety"), ("test_handoff_chat.lua", "handoff chat"), ("test_quiet_mode.lua", "quiet mode"), ("test_quick_hire.lua", "quick hire"), ("test_stop.lua", "stop"), ("test_ui_integration.lua", "integrated UI"), ("test_run_authorization.lua", "run authorization"), ("test_local_hire.lua", "local hire"), ("test_present_legacy.lua", "present legacy"), ("test_normal_legacy.lua", "normal legacy")]:
        run([args.luac, "-p", str(ROOT / "tests" / case)])
        output = run([args.lua, str(ROOT / "tests" / case)], cwd=ROOT / "tests")
        assert "Shir's Raid Builder " + label + " tests: PASS" in output

    for case, label in [("test_quick_final_choice.lua", "quick final choice"), ("test_planner_vanilla_ui.lua", "planner Vanilla UI"), ("test_quick_followup.lua", "quick followup"), ("test_random_hire.lua", "random hire"), ("test_random_runtime.lua", "random runtime"), ("test_planner.lua", "planner"), ("test_planner_ui.lua", "planner UI"), ("test_planner_execution.lua", "planner execution")]:
        run([args.luac, "-p", str(ROOT / "tests" / case)])
        output = run([args.lua, str(ROOT / "tests" / case)], cwd=ROOT / "tests")
        assert "Shir's Raid Builder " + label + " tests: PASS" in output

    for case, label in [("test_planner_refinements.lua", "planner refinements"), ("test_planner_roster.lua", "planner roster"), ("test_planner_priority.lua", "planner priority"), ("test_planner_player.lua", "planner player")]:
        run([args.luac, "-p", str(ROOT / "tests" / case)])
        output = run([args.lua, str(ROOT / "tests" / case)], cwd=ROOT / "tests")
        assert "Shir's Raid Builder " + label + " tests: PASS" in output

    for case, label in [("test_planner_sources_compact.lua", "compact sources"), ("test_planner_sources_wrap.lua", "sources wrap"), ("test_planner_selectors.lua", "composition selectors"), ("test_planner_composition_render.lua", "composition rendering"), ("test_planner_staged_groups.lua", "staged grouping")]:
        run([args.luac, "-p", str(ROOT / "tests" / case)])
        output = run([args.lua, str(ROOT / "tests" / case)], cwd=ROOT / "tests")
        assert "Shir's Raid Builder " + label + " tests: PASS" in output

    for case in ("test_planner_constraints.lua", "test_planner_identities.lua", "test_planner_human_tail.lua", "test_planner_save_gold.lua", "test_planner_quotes.lua", "test_planner_linked_quotes.lua", "test_planner_quote_safety.lua", "test_planner_quote_curve.lua", "test_planner_caster_block.lua", "test_planner_estimates.lua", "test_planner_race_defaults.lua", "test_planner_auto_sync.lua", "test_planner_draft_totals.lua", "test_planner_tab_selection.lua", "test_visible_plan_prices.lua", "test_visible_price_ordinals.lua", "test_visible_price_safety.lua", "test_visible_native_sync.lua", "test_planner_ultra.lua", "test_planner_ultra_ui.lua", "test_planner_wheel_dropdown.lua"):
        run([args.luac, "-p", str(ROOT / "tests" / case)])
        output = run([args.lua, str(ROOT / "tests" / case)], cwd=ROOT / "tests")
        assert "tests: PASS" in output, case

    for case in ("test_pricing_bounds.lua", "test_native_review.lua", "test_ultra_priority.lua", "test_ultra_global.lua", "test_save_plan.lua", "test_price_persistence.lua", "test_quote_rate.lua", "test_hire_footer.lua", "test_human_remove.lua"):
        run([args.luac, "-p", str(ROOT / "tests" / case)])
        output = run([args.lua, str(ROOT / "tests" / case)], cwd=ROOT / "tests")
        assert "tests: PASS" in output, case

    for case in ("test_performance_transactions.lua", "test_performance_quotes.lua", "test_performance_pools.lua"):
        run([args.luac, "-p", str(ROOT / "tests" / case)])
        output = run([args.lua, str(ROOT / "tests" / case)], cwd=ROOT / "tests")
        assert "0 failed" in output, case

    run([args.luac, "-p", str(ROOT / "tests" / "test_board_plan_lifecycle.lua")])
    lifecycle_output = run([args.lua, str(ROOT / "tests" / "test_board_plan_lifecycle.lua")], cwd=ROOT / "tests")
    assert "board plan lifecycle: PASS" in lifecycle_output

    run([args.luac, "-p", str(ROOT / "tests" / "test_login_player.lua")])
    login_output = run([args.lua, str(ROOT / "tests" / "test_login_player.lua")], cwd=ROOT / "tests")
    assert "login player tests: PASS" in login_output
    with tempfile.TemporaryDirectory(prefix="srb-login-") as temporary:
        saved = None
        for index, step in enumerate(("A", "B", "C", "C", "A")):
            destination = Path(temporary) / ("login-" + str(index) + ".lua")
            environment = os.environ.copy()
            environment["SRB_LOGIN_STEP"] = step
            environment["SRB_LOGIN_WRITE"] = str(destination)
            if saved is not None:
                environment["SRB_LOGIN_READ"] = str(saved)
            output = run([args.lua, str(ROOT / "tests" / "test_login_player.lua")], cwd=ROOT / "tests", env=environment)
            assert ("fresh login " + step + ": PASS") in output
            assert destination.is_file(), "login did not serialize its SavedVariable"
            saved = destination

    build_script = ROOT / "scripts" / "build_release.py"
    run([sys.executable, str(build_script)])
    release = ROOT / "dist" / ("ShirsRaidBuilder-" + version + ".zip")
    first_zip = release.read_bytes()
    run([sys.executable, str(build_script)])
    second_zip = release.read_bytes()
    assert first_zip == second_zip, "release ZIP is not reproducible"

    expected_members = ["ShirsRaidBuilder/" + relative for relative in RELEASE_FILES]
    with zipfile.ZipFile(release, "r") as archive:
        assert archive.testzip() is None
        assert archive.namelist() == expected_members
        for info in archive.infolist():
            assert info.date_time == (2020, 1, 1, 0, 0, 0)
            assert info.extra == b""
            assert info.comment == b""

    with tempfile.TemporaryDirectory(prefix="srb-crlf-") as temporary:
        alternate_root = Path(temporary)
        alternate_addon = alternate_root / "addon" / "ShirsRaidBuilder"
        alternate_addon.mkdir(parents=True)
        for relative in RELEASE_FILES:
            payload = (ADDON / relative).read_bytes()
            payload = payload.replace(b"\r\n", b"\n").replace(b"\r", b"\n").replace(b"\n", b"\r\n")
            (alternate_addon / relative).write_bytes(payload)
        alternate_script = alternate_root / "scripts" / "build_release.py"
        alternate_script.parent.mkdir(parents=True)
        alternate_script.write_bytes(build_script.read_bytes())
        environment = os.environ.copy()
        environment["SRB_ROOT"] = str(alternate_root)
        result = subprocess.run([sys.executable, str(alternate_script)], capture_output=True, text=True, errors="replace", env=environment)
        assert result.returncode == 0, result.stdout + result.stderr
        assert (alternate_root / "dist" / release.name).read_bytes() == first_zip, "release changes between LF and CRLF checkouts"

    addon_text = "\n".join((ADDON / relative).read_text(encoding="utf-8") for relative in runtime_files)
    print("SHIRS_RAID_BUILDER_VALIDATION=PASS")
    print("PUBLIC_FILES=" + str(len(PUBLIC_FILES)))
    print("RELEASE_FILES=" + str(len(RELEASE_FILES)))
    print("SOURCE_SHA256=" + hashlib.sha256(addon_text.encode("utf-8")).hexdigest())
    print("ZIP_SHA256=" + hashlib.sha256(first_zip).hexdigest())
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, OSError, ValueError, zipfile.BadZipFile) as exc:
        print("VALIDATION_FAILED: " + str(exc), file=sys.stderr)
        sys.exit(1)
