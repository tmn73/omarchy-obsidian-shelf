"""The `board` list type: an Obsidian Kanban plugin board.

Lanes are `## ` headings, cards are `- [ ]` lines with their indented lines,
and dates are `@{YYYY-MM-DD}` and `@@{HH:mm}` at the end of a card. The board
ends at `***` (the plugin's archive) or at its settings block; nothing after
that point is read or changed.
"""

import json
import re
from pathlib import Path

from shelf_io import fail, locate, locate_for_write, one_line, read_text, write_lines

LANE_RE = re.compile(r"^## (.+?)\s*$")
LIMIT_RE = re.compile(r"\s*\(\d+\)$")
CARD_RE = re.compile(r"^[-*] \[([ xX])\] ?(.*)$")
ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
CLOCK = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")
SETTINGS = "%% kanban:settings"
COMPLETE = "**Complete**"


def front_matter_end(lines: list) -> int:
    if lines and lines[0].strip() == "---":
        for index in range(1, len(lines)):
            if lines[index].strip() == "---":
                return index + 1
    return 0


def board_end(lines: list, start: int) -> int:
    for index in range(start, len(lines)):
        if lines[index].strip() == "***" or lines[index].startswith(SETTINGS):
            return index
    return len(lines)


def board_settings(lines: list, end: int) -> dict:
    """The JSON of the settings block, or {} when there is none."""
    for index in range(end, len(lines)):
        if lines[index].startswith(SETTINGS):
            fences = [i for i in range(index + 1, len(lines)) if lines[i].strip().startswith("```")]
            if len(fences) >= 2:
                try:
                    data = json.loads("\n".join(lines[fences[0] + 1:fences[1]]))
                    return data if isinstance(data, dict) else {}
                except ValueError:
                    return {}
    return {}


class Tokens:
    """The date and time tokens of a board, with its own triggers."""

    def __init__(self, settings: dict):
        self.date_trigger = str(settings.get("date-trigger") or "@")
        self.time_trigger = str(settings.get("time-trigger") or "@@")
        triggers = sorted([("time", self.time_trigger), ("date", self.date_trigger)], key=lambda t: -len(t[1]))
        self.patterns = [(kind, re.compile(re.escape(trigger) + r"\{([^}]*)\}")) for kind, trigger in triggers]

    def split(self, body: str) -> tuple:
        """(text without tokens, date, time, the tokens in their order)."""
        found = {"date": "", "time": ""}
        spans = []
        rest = body
        for kind, pattern in self.patterns:
            for match in pattern.finditer(rest):
                if not found[kind]:
                    found[kind] = match.group(1)
                spans.append((body.find(match.group(0)), match.group(0)))
            rest = pattern.sub(" ", rest)
        tokens = [token for _, token in sorted(spans)]
        return " ".join(rest.split()), found["date"], found["time"], tokens

    def date(self, value: str) -> str:
        return f"{self.date_trigger}{{{value}}}"

    def time(self, value: str) -> str:
        return f"{self.time_trigger}{{{value}}}"


def parse_board(lines: list) -> dict:
    start = front_matter_end(lines)
    end = board_end(lines, start)
    settings = board_settings(lines, end)
    tokens = Tokens(settings)
    lanes = []
    seen = {}
    index = start
    while index < end:
        line = lines[index]
        lane = LANE_RE.match(line)
        if lane:
            lanes.append({"title": LIMIT_RE.sub("", lane.group(1)), "line": index, "complete": False,
                          "marker": None, "cards": [], "opened": False})
            index += 1
            continue
        current = lanes[-1] if lanes else None
        card = CARD_RE.match(line)
        if current is not None and card:
            stop = index + 1
            while stop < end and lines[stop][:1] in (" ", "\t") and lines[stop].strip():
                stop += 1
            text, date, time, _ = tokens.split(card.group(2))
            seen[text] = seen.get(text, 0) + 1
            key = text if seen[text] == 1 else f"{text} #{seen[text]}"
            current["cards"].append({"key": key, "text": text, "date": date, "time": time,
                                     "checked": card.group(1) != " ", "start": index, "end": stop})
            current["opened"] = True
            index = stop
            continue
        if current is not None and line.strip() and not current["opened"]:
            current["opened"] = True
            if line.strip() == COMPLETE:
                current["complete"] = True
                current["marker"] = index
        index += 1
    date_format = settings.get("date-format")
    return {"lanes": lanes, "start": start, "end": end, "tokens": tokens,
            "datesOn": date_format in (None, "", "YYYY-MM-DD")}


def is_board(lines: list) -> bool:
    """A board has the key `kanban-plugin` in its front matter."""
    end = front_matter_end(lines)
    return any(line.startswith("kanban-plugin:") for line in lines[1:max(0, end - 1)])


def open_card_count(lines: list) -> int:
    return sum(len(lane["cards"]) for lane in parse_board(lines)["lanes"] if not lane["complete"])


def skeleton(lanes: list) -> str:
    """A new board as the Kanban plugin writes it; the last lane is Complete."""
    lanes = [name.strip() for name in lanes if name.strip()] or ["To do", "In progress", "Done"]
    body = "".join(f"## {name}\n\n" + ("**Complete**\n\n\n\n" if i == len(lanes) - 1 else "\n\n")
                   for i, name in enumerate(lanes))
    return "---\n\nkanban-plugin: board\n\n---\n\n" + body + "%% kanban:settings\n```\n" + \
        json.dumps({"kanban-plugin": "board"}, separators=(",", ":")) + "\n```\n%%\n"


def read_board(vault: Path, cfg: dict) -> dict:
    path, problem = locate(vault, cfg)
    if problem:
        return problem
    try:
        board = parse_board(read_text(path).split("\n"))
    except OSError as err:
        return {"id": cfg["id"], "state": "error", "message": str(err)}
    lanes = [{"title": lane["title"], "complete": lane["complete"],
              "items": [{k: c[k] for k in ("key", "text", "date", "time", "checked")} for c in lane["cards"]]}
             for lane in board["lanes"]]
    return {"id": cfg["id"], "state": "ok", "datesOn": board["datesOn"], "lanes": lanes}


# ---- Writes. Each one reads the file again and finds the card by its key.

def load(vault: Path, cfg: dict):
    path, problem = locate_for_write(vault, cfg)
    if problem:
        return None, None, problem
    try:
        return path, read_text(path).split("\n"), None
    except OSError as err:
        return None, None, fail("io", str(err))


def find_card(board: dict, key: str):
    for lane_index, lane in enumerate(board["lanes"]):
        for card in lane["cards"]:
            if card["key"] == key:
                return lane_index, card
    return None, None


def insert_point(lane: dict) -> int:
    """Where a new card goes: after the last card, the Complete marker or the heading."""
    if lane["cards"]:
        return lane["cards"][-1]["end"]
    if lane["marker"] is not None:
        return lane["marker"] + 1
    return lane["line"] + 1


def set_box(line: str, checked: bool) -> str:
    return re.sub(r"^([-*]) \[[ xX]\]", r"\1 [x]" if checked else r"\1 [ ]", line, count=1)


def change_card(vault: Path, cfg: dict, key: str, change) -> dict:
    """Apply change(lines, board, lane_index, card) -> lines or a failure dict."""
    path, lines, problem = load(vault, cfg)
    if problem:
        return problem
    board = parse_board(lines)
    lane_index, card = find_card(board, key)
    if card is None:
        return fail("changed", "The card is no longer there")
    out = change(lines, board, lane_index, card)
    if isinstance(out, dict):
        return out
    return write_lines(path, out)


def moved(lines: list, card: dict, title: str, checked: bool):
    """Take the card block out and put it at the end of the lane named title."""
    block = lines[card["start"]:card["end"]]
    block[0] = set_box(block[0], checked)
    rest = lines[:card["start"]] + lines[card["end"]:]
    lane = next((l for l in parse_board(rest)["lanes"] if l["title"] == title), None)
    if lane is None:
        return fail("changed", f"The lane {title} is no longer there")
    at = insert_point(lane)
    return rest[:at] + block + rest[at:]


def add_board(vault: Path, cfg: dict, title: str, text: str) -> dict:
    text = one_line(text)
    if not text:
        return fail("invalid", "The text is empty")
    path, lines, problem = load(vault, cfg)
    if problem:
        return problem
    lane = next((l for l in parse_board(lines)["lanes"] if l["title"] == title), None)
    if lane is None:
        return fail("changed", f"The lane {title} is no longer there")
    at = insert_point(lane)
    return write_lines(path, lines[:at] + [f"- [{'x' if lane['complete'] else ' '}] {text}"] + lines[at:])


def move_board(vault: Path, cfg: dict, key: str, title: str) -> dict:
    def change(lines, board, lane_index, card):
        target = next((l for l in board["lanes"] if l["title"] == title), None)
        if target is None:
            return fail("changed", f"The lane {title} is no longer there")
        return moved(lines, card, title, target["complete"])
    return change_card(vault, cfg, key, change)


def done_board(vault: Path, cfg: dict, key: str) -> dict:
    """Tick: to the Complete lane, or back to the first lane from it."""
    def change(lines, board, lane_index, card):
        lanes = board["lanes"]
        if lanes[lane_index]["complete"]:
            first = next((l for l in lanes if not l["complete"]), None)
            if first is None:
                lines[card["start"]] = set_box(lines[card["start"]], False)
                return lines
            return moved(lines, card, first["title"], False)
        complete = next((l for l in lanes if l["complete"]), None)
        if complete is None:
            lines[card["start"]] = set_box(lines[card["start"]], True)
            return lines
        return moved(lines, card, complete["title"], True)
    return change_card(vault, cfg, key, change)


def card_parts(line: str, tokens: Tokens) -> tuple:
    """(prefix, text, date, time, tokens) of a card line."""
    match = CARD_RE.match(line)
    prefix = line[:match.start(2)]
    text, date, time, found = tokens.split(match.group(2))
    return prefix, text, date, time, found


def date_board(vault: Path, cfg: dict, key: str, date: str, time: str, today: str) -> dict:
    date, time = (date or "").strip(), (time or "").strip()
    if date and not ISO_DATE.match(date) or time and not CLOCK.match(time):
        return fail("invalid", "A date is YYYY-MM-DD and a time is HH:MM")
    if time and not date:
        date = today

    def change(lines, board, lane_index, card):
        if not board["datesOn"]:
            return fail("invalid", "This board uses another date format")
        tokens = board["tokens"]
        prefix, text, _, _, _ = card_parts(lines[card["start"]], tokens)
        parts = [text] + ([tokens.date(date)] if date else []) + ([tokens.time(time)] if time else [])
        lines[card["start"]] = prefix + " ".join(parts)
        return lines
    return change_card(vault, cfg, key, change)


def edit_board(vault: Path, cfg: dict, key: str, text: str) -> dict:
    text = one_line(text)
    if not text:
        return fail("invalid", "The text is empty")

    def change(lines, board, lane_index, card):
        prefix, _, _, _, found = card_parts(lines[card["start"]], board["tokens"])
        lines[card["start"]] = prefix + " ".join([text] + found)
        return lines
    return change_card(vault, cfg, key, change)


def remove_board(vault: Path, cfg: dict, key: str) -> dict:
    def change(lines, board, lane_index, card):
        return lines[:card["start"]] + lines[card["end"]:]
    return change_card(vault, cfg, key, change)


def clear_board(vault: Path, cfg: dict) -> dict:
    """Remove every card of the Complete lanes; headings and markers stay."""
    path, lines, problem = load(vault, cfg)
    if problem:
        return problem
    blocks = [c for lane in parse_board(lines)["lanes"] if lane["complete"] for c in lane["cards"]]
    for card in sorted(blocks, key=lambda c: -c["start"]):
        del lines[card["start"]:card["end"]]
    return write_lines(path, lines)


def add_lane(vault: Path, cfg: dict, title: str) -> dict:
    """Add a `## title` lane before the Complete lane, or at the end of the board."""
    title = one_line(title).lstrip("#").strip()
    if not title:
        return fail("invalid", "The lane needs a name")
    path, lines, problem = load(vault, cfg)
    if problem:
        return problem
    board = parse_board(lines)
    if any(lane["title"].lower() == title.lower() for lane in board["lanes"]):
        return fail("invalid", f"A lane named {title} is already there")
    complete = next((lane for lane in board["lanes"] if lane["complete"]), None)
    block = [f"## {title}", "", "", ""]
    if complete is not None:
        at = complete["line"]
    else:
        at = board["end"]
        if at == len(lines) and lines and lines[-1] == "":
            at -= 1
        if at > 0 and lines[at - 1].strip():
            block = [""] + block
    return write_lines(path, lines[:at] + block + lines[at:])
