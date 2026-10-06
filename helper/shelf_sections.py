"""The `sections` list type: top-level bullets grouped under headings."""

import re
from pathlib import Path

from shelf_io import locate, read_text

HEADING_RE = re.compile(r"^#{1,6} (.+)$")
ITEM_RE = re.compile(r"^[-*] (.+)$")


def parse_sections(lines: list) -> list:
    """Return [{"heading", "line", "items": [{"line", "text"}]}] in file order."""
    sections = []
    for index, line in enumerate(lines):
        heading = HEADING_RE.match(line)
        if heading:
            sections.append({"heading": heading.group(1).strip(), "line": index, "items": []})
            continue
        item = ITEM_RE.match(line)
        if item and sections:
            sections[-1]["items"].append({"line": index, "text": item.group(1)})
    return sections


def read_sections(vault: Path, cfg: dict) -> dict:
    path, problem = locate(vault, cfg)
    if problem:
        return problem
    try:
        lines = read_text(path).split("\n")
    except OSError as err:
        return {"id": cfg["id"], "state": "error", "message": str(err)}
    sections = [
        {
            "heading": s["heading"],
            "items": [{"key": s["heading"] + "\n" + lines[i["line"]], "text": i["text"]} for i in s["items"]],
        }
        for s in parse_sections(lines)
    ]
    return {"id": cfg["id"], "state": "ok", "sections": sections}
