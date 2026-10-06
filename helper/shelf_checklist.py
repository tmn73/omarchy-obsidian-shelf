"""The `checklist` list type: one `- [ ] text` line is one item."""

import re
from pathlib import Path

from shelf_io import locate, read_text

OPEN_RE = re.compile(r"^[-*] \[ \] (.+)$")


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
