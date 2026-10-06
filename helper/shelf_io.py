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
