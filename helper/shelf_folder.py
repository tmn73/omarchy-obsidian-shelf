"""The `folder` list type: one note in a folder is one item."""

import json
import os
import re
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse

from shelf_previews import merge_preview
from shelf_io import OutsideVault, atomic_write, fail, locate, locate_for_write, ok, one_line, read_text, resolve_in_vault

FRONT_MATTER_URL_KEYS = ("url", "source", "link")
URL_RE = re.compile(r"https?://[^\s)>\]]+")
LINK_RE = re.compile(r"\[([^\]]*)\]\([^)]*\)")
WIKILINKS_ONLY_RE = re.compile(r"^(\s*\[\[[^\]]*\]\]\s*)+$")
IMAGE_RE = re.compile(r"!\[[^\]]*\]\((https?://[^)\s]+)\)")
YOUTUBE_RE = re.compile(
    r"(?:youtube\.com/(?:watch\?(?:[^\s)]*&)?v=|embed/|shorts/)|youtube-nocookie\.com/embed/|youtu\.be/)([A-Za-z0-9_-]{11})"
)
TAG_RE = re.compile(r"<[^>]+>")
PIC_LINK_RE = re.compile(r"\s*\bpic\.twitter\.com/\S+")
FRONT_MATTER_IMAGE_KEYS = ("image", "cover", "thumbnail", "banner")
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
                    meta[key.strip().lower()] = front_matter_value(value)
            return meta, "\n".join(lines[end + 1:])
    return {}, text


def front_matter_value(raw: str) -> str:
    value = raw.strip()
    if value.startswith('"'):
        try:
            return str(json.loads(value))
        except ValueError:
            pass
    return value.strip("\"'")


def reduce_links(text: str) -> str:
    return LINK_RE.sub(lambda m: m.group(1), text)


def note_title(meta: dict, body: str, fallback: str) -> str:
    if meta.get("title"):
        return meta["title"]
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
        if (not stripped or stripped.startswith("#") or stripped.startswith("<")
                or WIKILINKS_ONLY_RE.match(stripped) or IMAGE_RE.fullmatch(stripped)):
            continue
        if stripped.startswith(">"):
            stripped = stripped[1:].strip()
        text = reduce_links(IMAGE_RE.sub("", stripped))
        text = PIC_LINK_RE.sub("", TAG_RE.sub("", text))
        text = " ".join(text.split())
        if text:
            return text[:EXCERPT_MAX]
    return ""


def note_image(meta: dict, body: str, url: str) -> str:
    """A picture for the row: front matter, else the first Markdown image,
    else the YouTube thumbnail of the video the note points to."""
    for key in FRONT_MATTER_IMAGE_KEYS:
        if URL_RE.match(meta.get(key, "")):
            return meta[key]
    match = IMAGE_RE.search(body)
    if match:
        return match.group(1)
    video = YOUTUBE_RE.search(url) or YOUTUBE_RE.search(body)
    if video:
        return f"https://i.ytimg.com/vi/{video.group(1)}/mqdefault.jpg"
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
    title = note_title(meta, body, "")
    return {
        "key": path.relative_to(vault_root).as_posix(),
        "title": title or path.stem,
        "titleFromNote": title != "",
        "excerpt": note_excerpt(body),
        "url": url,
        "domain": url_domain(url),
        "image": note_image(meta, body, url),
        "modifiedAt": iso_mtime(path),
    }


def read_folder(vault: Path, cfg: dict, previews=None) -> dict:
    list_id = cfg["id"]
    folder, problem = locate(vault, cfg, want_dir=True)
    if problem:
        return problem
    root = Path(vault).resolve()
    try:
        notes = [p for p in folder.iterdir() if p.is_file() and p.suffix == ".md"]
        notes.sort(key=lambda p: p.stat().st_mtime, reverse=True)
        items = [merge_preview(folder_item(root, p), previews or {}) for p in notes]
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


def locate_note(vault: Path, cfg: dict, key: str):
    """Return (note path, None), or (None, an action failure)."""
    folder, problem = locate_for_write(vault, cfg, want_dir=True)
    if problem:
        return None, problem
    try:
        note = resolve_in_vault(vault, key)
    except OutsideVault as err:
        return None, fail("invalid", str(err))
    if note.parent != folder or note.suffix != ".md":
        return None, fail("invalid", f"{key} is not a note of {cfg['path']}")
    if not note.is_file():
        return None, fail("changed", f"{key} is no longer there")
    return note, None


def done_folder(vault: Path, cfg: dict, key: str) -> dict:
    """Move one note of the folder to the Obsidian trash of the vault."""
    note, problem = locate_note(vault, cfg, key)
    if problem:
        return problem
    trash = Path(vault).resolve() / ".trash"
    try:
        trash.mkdir(exist_ok=True)
        os.rename(note, trash_target(trash, note.name))
    except OSError as err:
        return fail("io", str(err))
    return ok()


def edit_folder(vault: Path, cfg: dict, key: str, text: str) -> dict:
    """Set the title shown for a note in the `title` key of its front matter.

    The body stays as it is: a ReadItLater heading is a link, and rewriting it
    would lose the link.
    """
    text = one_line(text)
    if not text:
        return fail("invalid", "The text is empty")
    note, problem = locate_note(vault, cfg, key)
    if problem:
        return problem
    title_line = "title: " + json.dumps(text, ensure_ascii=False)
    try:
        lines = read_text(note).split("\n")
        end = front_matter_end(lines)
        if end is None:
            lines = ["---", title_line, "---"] + lines
        else:
            kept = [line for line in lines[1:end] if line.partition(":")[0].strip().lower() != "title"]
            lines = ["---", title_line] + kept + lines[end:]
        atomic_write(note, "\n".join(lines))
    except OSError as err:
        return fail("io", str(err))
    return ok()


def front_matter_end(lines: list):
    """The index of the closing `---` of a leading front matter block, or None."""
    if not lines or lines[0].strip() != "---":
        return None
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            return index
    return None
