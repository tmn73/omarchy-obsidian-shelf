"""The `folder` list type: one note in a folder is one item."""

import os
import re
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse

from shelf_io import OutsideVault, fail, locate, locate_for_write, ok, read_text, resolve_in_vault

FRONT_MATTER_URL_KEYS = ("url", "source", "link")
URL_RE = re.compile(r"https?://[^\s)>\]]+")
LINK_RE = re.compile(r"\[([^\]]*)\]\([^)]*\)")
WIKILINKS_ONLY_RE = re.compile(r"^(\s*\[\[[^\]]*\]\]\s*)+$")
EXCERPT_MAX = 200


def split_front_matter(text: str):
    """Return (front matter dict, body) for a leading `---` block."""
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return {}, text
    for end in range(1, len(lines)):
        if lines[end].strip() == "---":
            meta = {}
            for line in lines[1:end]:
                key, sep, value = line.partition(":")
                if sep:
                    meta[key.strip().lower()] = value.strip().strip("\"'")
            return meta, "\n".join(lines[end + 1:])
    return {}, text


def reduce_links(text: str) -> str:
    return LINK_RE.sub(lambda m: m.group(1), text)


def note_title(body: str, fallback: str) -> str:
    for line in body.split("\n"):
        if line.startswith("# "):
            title = reduce_links(line[2:]).strip()
            if title:
                return title
    return fallback


def note_url(meta: dict, body: str) -> str:
    for key in FRONT_MATTER_URL_KEYS:
        if URL_RE.match(meta.get(key, "")):
            return meta[key]
    match = URL_RE.search(body)
    return match.group(0) if match else ""


def note_excerpt(body: str) -> str:
    for line in body.split("\n"):
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or WIKILINKS_ONLY_RE.match(stripped):
            continue
        if stripped.startswith(">"):
            stripped = stripped[1:].strip()
        text = reduce_links(stripped).strip()
        if text:
            return text[:EXCERPT_MAX]
    return ""


def url_domain(url: str) -> str:
    if not url:
        return ""
    host = urlparse(url).hostname or ""
    return host[4:] if host.startswith("www.") else host


def iso_mtime(path: Path) -> str:
    stamp = datetime.fromtimestamp(path.stat().st_mtime).astimezone()
    return stamp.isoformat(timespec="seconds")


def folder_item(vault_root: Path, path: Path) -> dict:
    meta, body = split_front_matter(read_text(path))
    url = note_url(meta, body)
    return {
        "key": path.relative_to(vault_root).as_posix(),
        "title": note_title(body, path.stem),
        "excerpt": note_excerpt(body),
        "url": url,
        "domain": url_domain(url),
        "modifiedAt": iso_mtime(path),
    }


def read_folder(vault: Path, cfg: dict) -> dict:
    list_id = cfg["id"]
    folder, problem = locate(vault, cfg, want_dir=True)
    if problem:
        return problem
    root = Path(vault).resolve()
    try:
        notes = [p for p in folder.iterdir() if p.is_file() and p.suffix == ".md"]
        notes.sort(key=lambda p: p.stat().st_mtime, reverse=True)
        items = [folder_item(root, p) for p in notes]
    except OSError as err:
        return {"id": list_id, "state": "error", "message": str(err)}
    return {"id": list_id, "state": "ok", "items": items}


def trash_target(trash: Path, name: str) -> Path:
    stem, suffix = Path(name).stem, Path(name).suffix
    candidate, n = trash / name, 0
    while candidate.exists():
        n += 1
        candidate = trash / f"{stem} {n}{suffix}"
    return candidate


def done_folder(vault: Path, cfg: dict, key: str) -> dict:
    """Move one note of the folder to the Obsidian trash of the vault."""
    folder, problem = locate_for_write(vault, cfg, want_dir=True)
    if problem:
        return problem
    try:
        note = resolve_in_vault(vault, key)
    except OutsideVault as err:
        return fail("invalid", str(err))
    if note.parent != folder or note.suffix != ".md":
        return fail("invalid", f"{key} is not a note of {cfg['path']}")
    if not note.is_file():
        return fail("changed", f"{key} is no longer there")
    trash = Path(vault).resolve() / ".trash"
    try:
        trash.mkdir(exist_ok=True)
        os.rename(note, trash_target(trash, note.name))
    except OSError as err:
        return fail("io", str(err))
    return ok()
