"""File access shared by every list type.

Every path the helper touches goes through resolve_in_vault, so a list path
can never reach a file outside the vault. Every write goes through
atomic_write, so a reader (Obsidian, a sync client) never sees a half file.
"""

import os
import tempfile
from pathlib import Path


class OutsideVault(ValueError):
    """The list path resolves to a place outside the vault."""


def resolve_in_vault(vault: Path, rel: str) -> Path:
    root = Path(vault).resolve()
    target = (root / rel).resolve()
    if target != root and root not in target.parents:
        raise OutsideVault(f"{rel} is outside the vault")
    return target


def locate(vault: Path, cfg: dict, want_dir: bool = False):
    """Return (path, None), or (None, a list state dict) when it cannot be used."""
    list_id, rel = cfg["id"], cfg["path"]
    try:
        path = resolve_in_vault(vault, rel)
    except OutsideVault as err:
        return None, {"id": list_id, "state": "error", "message": str(err)}
    exists = path.is_dir() if want_dir else path.is_file()
    if not exists:
        return None, {"id": list_id, "state": "missing", "message": f"{rel} not found"}
    return path, None


def ok() -> dict:
    return {"ok": True}


def fail(code: str, message: str) -> dict:
    return {"ok": False, "error": code, "message": message}


def locate_for_write(vault: Path, cfg: dict, want_dir: bool = False):
    """Like locate, but the problem comes back as an action failure."""
    path, problem = locate(vault, cfg, want_dir)
    if problem:
        code = "missing" if problem["state"] == "missing" else "invalid"
        return None, fail(code, problem["message"])
    return path, None


def one_line(text: str) -> str:
    """The text of a new item: trimmed, line breaks folded to spaces."""
    return " ".join(part.strip() for part in str(text).splitlines() if part.strip())


def read_text(path: Path) -> str:
    return Path(path).read_text(encoding="utf-8")


def atomic_write(path: Path, text: str) -> None:
    path = Path(path)
    fd, tmp = tempfile.mkstemp(prefix=".shelf-", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        if path.exists():
            os.chmod(tmp, path.stat().st_mode & 0o777)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def write_lines(path: Path, lines: list) -> dict:
    """Write lines joined by newlines, and report an action result."""
    try:
        atomic_write(path, "\n".join(lines))
    except OSError as err:
        return fail("io", str(err))
    return ok()
