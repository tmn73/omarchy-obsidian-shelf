"""The items the user has seen, shared by every bar on every screen.

Each screen runs its own copy of the widget. The seen state lives in one file,
so closing the popup on one screen clears the chip on all of them, and a shell
restart keeps it. The file holds, for each list, the vault path the keys were
read from and the item keys:

    {"todo": {"path": "Todo.md", "type": "checklist", "keys": ["- [ ] a"]}}

A list read from another path, or as another type, starts over: its keys
mean something else.
"""

import json
from pathlib import Path

from shelf_io import atomic_write, ok


def state_file(env: dict, home: Path) -> Path:
    base = env.get("XDG_STATE_HOME") or Path(home) / ".local" / "state"
    return Path(base) / "obsidian-shelf" / "seen.json"


def load(path: Path) -> dict:
    """The stored state, or an empty one when the file is missing or broken."""
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    if not isinstance(data, dict):
        return {}
    out = {}
    for list_id, entry in data.items():
        if isinstance(entry, dict) and isinstance(entry.get("path"), str) and isinstance(entry.get("keys"), list):
            out[list_id] = {"path": entry["path"], "keys": [str(k) for k in entry["keys"]]}
            if isinstance(entry.get("type"), str):
                out[list_id]["type"] = entry["type"]
    return out


def list_keys(payload: dict) -> list:
    """The item keys of one list, in the order the reader gave them."""
    nested = "sections" if "sections" in payload else "lanes" if "lanes" in payload else ""
    groups = [group.get("items") or [] for group in payload.get(nested) or []] if nested else [payload.get("items") or []]
    return [item["key"] for items in groups for item in items]


def settle(seen: dict, lists: list, payloads: list) -> tuple:
    """Start a list the shelf has not seen yet with all its items seen.

    A list is new when the state has no entry for it, or when its entry was
    read from another path. A list that could not be read keeps its entry.
    Lists no longer on the shelf are dropped.
    """
    by_id = {p.get("id"): p for p in payloads}
    ids = {cfg.get("id") for cfg in lists}
    out = {list_id: entry for list_id, entry in seen.items() if list_id in ids}
    changed = len(out) != len(seen)
    for cfg in lists:
        payload = by_id.get(cfg.get("id"))
        if payload is None or payload.get("state") != "ok":
            continue
        entry = out.get(cfg["id"])
        kind = cfg.get("type", "")
        if entry is None or entry["path"] != cfg.get("path") or entry.get("type", kind) != kind:
            out[cfg["id"]] = {"path": cfg.get("path", ""), "type": kind, "keys": list_keys(payload)}
            changed = True
        elif "type" not in entry:
            out[cfg["id"]] = dict(entry, type=kind)
            changed = True
    return out, changed


def save(path: Path, seen: dict) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    atomic_write(path, json.dumps(seen, ensure_ascii=False) + "\n")


def mark(path: Path, lists: list, keys_by_list: dict) -> dict:
    """Store the keys the user has just seen, for the lists on the shelf."""
    configs = {cfg.get("id"): cfg for cfg in lists}
    seen = load(path)
    for list_id, keys in keys_by_list.items():
        if list_id in configs:
            cfg = configs[list_id]
            seen[list_id] = {"path": cfg.get("path", ""), "type": cfg.get("type", ""), "keys": [str(k) for k in keys]}
    save(path, seen)
    return ok()
