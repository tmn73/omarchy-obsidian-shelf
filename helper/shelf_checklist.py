"""The `checklist` list type: one `- [ ] text` line is one item."""

import re
from pathlib import Path

from shelf_io import atomic_write, fail, locate, locate_for_write, ok, one_line, read_text, resolve_in_vault, write_lines

OPEN_RE = re.compile(r"^[-*] \[ \] (.+)$")
CHECKED_RE = re.compile(r"^[-*] \[[xX]\] ")


def read_checklist(vault: Path, cfg: dict) -> dict:
    path, problem = locate(vault, cfg)
    if problem:
        return problem
    try:
        lines = read_text(path).split("\n")
    except OSError as err:
        return {"id": cfg["id"], "state": "error", "message": str(err)}
    items = []
    for line in lines:
        match = OPEN_RE.match(line)
        if match:
            items.append({"key": line, "text": match.group(1)})
    return {"id": cfg["id"], "state": "ok", "items": items}


def rewrite_item(vault: Path, cfg: dict, key: str, change) -> dict:
    """Re-read the file, find the item line by its text, apply change(lines, index)."""
    path, problem = locate_for_write(vault, cfg)
    if problem:
        return problem
    try:
        lines = read_text(path).split("\n")
    except OSError as err:
        return fail("io", str(err))
    if key not in lines or not OPEN_RE.match(key):
        return fail("changed", "The item is no longer there")
    lines = change(lines, lines.index(key))
    if cfg.get("onDone") != "check":
        lines = [line for line in lines if not CHECKED_RE.match(line)]
    return write_lines(path, lines)


def done_checklist(vault: Path, cfg: dict, key: str) -> dict:
    """Tick one item: remove its line, or write [x] with onDone "check"."""
    def change(lines, index):
        if cfg.get("onDone") == "check":
            lines[index] = key[:2] + "[x]" + key[5:]
        else:
            del lines[index]
        return lines
    return rewrite_item(vault, cfg, key, change)


def remove_checklist(vault: Path, cfg: dict, key: str) -> dict:
    """Remove one item without ticking it, whatever onDone says."""
    def change(lines, index):
        del lines[index]
        return lines
    return rewrite_item(vault, cfg, key, change)


def edit_checklist(vault: Path, cfg: dict, key: str, text: str) -> dict:
    """Replace the text of one item, and keep its bullet and its box."""
    text = one_line(text)
    if not text:
        return fail("invalid", "The text is empty")
    def change(lines, index):
        lines[index] = key[:6] + text
        return lines
    return rewrite_item(vault, cfg, key, change)


def add_checklist(vault: Path, cfg: dict, text: str) -> dict:
    """Append `- [ ] text` at the end of the file, and create the file if needed."""
    text = one_line(text)
    if not text:
        return fail("invalid", "The text is empty")
    path, problem = locate_for_write(vault, cfg)
    if problem and problem["error"] != "missing":
        return problem
    if problem:
        path = resolve_in_vault(vault, cfg["path"])
    try:
        current = read_text(path) if path.exists() else ""
    except OSError as err:
        return fail("io", str(err))
    if current and not current.endswith("\n"):
        current += "\n"
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        atomic_write(path, current + f"- [ ] {text}\n")
    except OSError as err:
        return fail("io", str(err))
    return ok()
