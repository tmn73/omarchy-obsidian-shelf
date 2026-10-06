"""What the settings and the first run need from the vault: the vaults Obsidian
knows, lists worth suggesting, the paths for the picker, and creating a new
list's folder or file.
"""

import json
import os
from pathlib import Path

from shelf_checklist import OPEN_RE
from shelf_folder import URL_RE
from shelf_io import OutsideVault, atomic_write, fail, read_text, resolve_in_vault
from shelf_sections import parse_sections

SCAN_LIMIT = 20


def known_vaults(registry: Path) -> list:
    """Vaults from Obsidian's own registry: the open one first, then the most recent."""
    try:
        vaults = json.loads(Path(registry).read_text(encoding="utf-8")).get("vaults") or {}
    except (OSError, ValueError, AttributeError):
        return []
    entries = [v for v in vaults.values() if isinstance(v, dict) and v.get("path")]
    entries.sort(key=lambda v: (not v.get("open", False), -float(v.get("ts", 0))))
    return [{"path": v["path"], "name": Path(v["path"]).name, "open": bool(v.get("open", False))} for v in entries]


def walk(vault: Path):
    """(folder, markdown files) for every folder of the vault, dot folders left out."""
    root = Path(vault).resolve()
    for folder, dirs, files in os.walk(root):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        yield Path(folder), sorted(f for f in files if f.endswith(".md"))


def scan(vault: Path) -> list:
    root = Path(vault).resolve()
    found = []
    for folder, files in walk(root):
        texts = {}
        for name in files:
            try:
                texts[name] = read_text(folder / name)
            except OSError:
                continue
        linky = sum(1 for text in texts.values() if URL_RE.search(text))
        if folder != root and linky and linky * 2 >= len(texts):
            found.append({"type": "folder", "path": folder.relative_to(root).as_posix(), "count": len(texts)})
        for name, text in texts.items():
            lines = text.split("\n")
            rel = (folder / name).relative_to(root).as_posix()
            open_items = sum(1 for line in lines if OPEN_RE.match(line))
            topics = sum(len(s["items"]) for s in parse_sections(lines))
            if open_items:
                found.append({"type": "checklist", "path": rel, "count": open_items})
            elif topics:
                found.append({"type": "sections", "path": rel, "count": topics})
    found.sort(key=lambda s: (-s["count"], s["path"]))
    return found[:SCAN_LIMIT]


def vault_paths(vault: Path, kind: str) -> list:
    root = Path(vault).resolve()
    out = []
    for folder, files in walk(root):
        if kind == "folder" and folder != root:
            out.append(folder.relative_to(root).as_posix())
        if kind == "file":
            out.extend((folder / name).relative_to(root).as_posix() for name in files)
    return sorted(out)


def create_list(vault: Path, cfg: dict, sections: list) -> dict:
    """Create the folder or file of a new list. An existing path is kept as it is."""
    try:
        path = resolve_in_vault(vault, cfg["path"])
    except OutsideVault as err:
        return fail("invalid", str(err))
    if path.exists():
        return {"ok": True, "created": False}
    try:
        if cfg.get("type") == "folder":
            path.mkdir(parents=True)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            text = "\n".join(f"## {name}\n" for name in sections if name.strip()) if cfg.get("type") == "sections" else ""
            atomic_write(path, text)
    except OSError as err:
        return fail("io", str(err))
    return {"ok": True, "created": True}
