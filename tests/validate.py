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
