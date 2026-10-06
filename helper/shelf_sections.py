"""The `sections` list type: top-level bullets grouped under headings."""

import re
from pathlib import Path

from shelf_io import fail, locate, locate_for_write, one_line, read_text, write_lines

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


def add_sections(vault: Path, cfg: dict, heading: str, text: str) -> dict:
    """Insert `- text` after the last item of the section, or after its heading."""
    text = one_line(text)
    if not text:
        return fail("invalid", "The text is empty")
    path, problem = locate_for_write(vault, cfg)
    if problem:
        return problem
    try:
        lines = read_text(path).split("\n")
    except OSError as err:
        return fail("io", str(err))
    section = next((s for s in parse_sections(lines) if s["heading"] == heading), None)
    if section is None:
        return fail("changed", f"The section {heading} is no longer there")
    anchor = section["items"][-1]["line"] if section["items"] else section["line"]
    lines.insert(anchor + 1, f"- {text}")
    return write_lines(path, lines)


def clear_sections(vault: Path, cfg: dict) -> dict:
    """Remove every item, keep the headings, the preamble and one blank line between sections."""
    path, problem = locate_for_write(vault, cfg)
    if problem:
        return problem
    try:
        lines = read_text(path).split("\n")
    except OSError as err:
        return fail("io", str(err))
    item_lines = {i["line"] for s in parse_sections(lines) for i in s["items"]}
    kept = []
    for index, line in enumerate(lines):
        if index in item_lines:
            continue
        if line.strip() == "" and kept and kept[-1].strip() == "":
            continue
        kept.append(line)
    return write_lines(path, kept)


def rewrite_topic(vault: Path, cfg: dict, key: str, change) -> dict:
    """Re-read the file, find the topic in its section by text, apply change(lines, index)."""
    heading, sep, line = str(key).partition("\n")
    if not sep:
        return fail("invalid", "A topic key is the heading, a newline, then the line")
    path, problem = locate_for_write(vault, cfg)
    if problem:
        return problem
    try:
        lines = read_text(path).split("\n")
    except OSError as err:
        return fail("io", str(err))
    section = next((s for s in parse_sections(lines) if s["heading"] == heading), None)
    match = next((i for i in section["items"] if lines[i["line"]] == line), None) if section else None
    if match is None:
        return fail("changed", "The topic is no longer there")
    return write_lines(path, change(lines, match["line"], line))


def remove_sections(vault: Path, cfg: dict, key: str) -> dict:
    def change(lines, index, line):
        del lines[index]
        return lines
    return rewrite_topic(vault, cfg, key, change)


def edit_sections(vault: Path, cfg: dict, key: str, text: str) -> dict:
    text = one_line(text)
    if not text:
        return fail("invalid", "The text is empty")
    def change(lines, index, line):
        lines[index] = line[:2] + text
        return lines
    return rewrite_topic(vault, cfg, key, change)
