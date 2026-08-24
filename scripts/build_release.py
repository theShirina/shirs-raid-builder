from __future__ import annotations

import hashlib
import os
from pathlib import Path
import re
import sys
import uuid
import zipfile

ROOT = Path(os.environ.get("SRB_ROOT", str(Path(__file__).resolve().parents[1]))).resolve()
ADDON = ROOT / "addon" / "ShirsRaidBuilder"
DIST = ROOT / "dist"
TOC = ADDON / "ShirsRaidBuilder.toc"
FIXED_TIME = (2020, 1, 1, 0, 0, 0)
RELEASE_FILES = [
    "ShirsRaidBuilder_Core.lua",
    "ShirsRaidBuilder_Abilities.lua",
    "ShirsRaidBuilder.lua",
    "ShirsRaidBuilder.toc",
    "LICENSE",
    "README.txt",
]


def version() -> str:
    match = re.search(r"^## Version:\s*(.+?)\s*$", TOC.read_text(encoding="utf-8"), re.MULTILINE)
    if not match:
        raise RuntimeError("TOC version is missing")
    return match.group(1)


def build() -> Path:
    present = sorted(path.name for path in ADDON.iterdir() if path.is_file())
    if present != sorted(RELEASE_FILES):
        raise RuntimeError("unexpected addon file set: " + ", ".join(present))

    DIST.mkdir(parents=True, exist_ok=True)
    output = DIST / ("ShirsRaidBuilder-" + version() + ".zip")
    temporary = DIST / (output.name + ".tmp-" + uuid.uuid4().hex)
    try:
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for relative in RELEASE_FILES:
                path = ADDON / relative
                info = zipfile.ZipInfo("ShirsRaidBuilder/" + relative, FIXED_TIME)
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                info.create_system = 3
                payload = path.read_bytes()
                if path.suffix.lower() in {".lua", ".toc", ".txt"} or path.name == "LICENSE":
                    payload = payload.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
                archive.writestr(info, payload)

        with zipfile.ZipFile(temporary, "r") as archive:
            if archive.testzip() is not None:
                raise RuntimeError("ZIP integrity check failed")
            expected = ["ShirsRaidBuilder/" + relative for relative in RELEASE_FILES]
            if archive.namelist() != expected:
                raise RuntimeError("ZIP member mismatch")
        os.replace(temporary, output)
    finally:
        if temporary.exists():
            temporary.unlink()
    return output


if __name__ == "__main__":
    try:
        result = build()
    except (OSError, RuntimeError, ValueError, zipfile.BadZipFile) as exc:
        print("BUILD_FAILED: " + str(exc), file=sys.stderr)
        sys.exit(1)
    print("ZIP=" + str(result))
    print("SHA256=" + hashlib.sha256(result.read_bytes()).hexdigest())
    print("BYTES=" + str(result.stat().st_size))
