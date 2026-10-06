# Obsidian Shelf Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans, inline in the current session. Never subagent-driven. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An Omarchy bar widget, `tmn73.obsidian` ("Obsidian Shelf"), that shows `folder`, `checklist` and `sections` lists from a Markdown vault and acts on them from the bar.

**Architecture:** A Python helper (standard library only) is the only code that reads or writes the vault. `Service.qml` runs it and keeps the last good payload. `Model.js` holds the pure logic. Small QML components render direction A of the design canvas, with keyed `ListModel`s so that rows animate in and out.

**Tech Stack:** Python 3 stdlib (`unittest`), QML on Quickshell with the Omarchy shell modules `qs.Commons` and `qs.Ui`, plain JS under `node --test`, bash for source checks.

**Spec:** `docs/superpowers/specs/2026-10-06-obsidian-shelf-design.md`

## Global Constraints

- Plugin ID `tmn73.obsidian`. Name "Obsidian Shelf". Repository `~/dev/omarchy-obsidian-shelf`, remote `tmn73/omarchy-obsidian-shelf`.
- Git identity is already set locally: `tmn73 <tommymartin1234@gmail.com>`. Commit messages in English. Do not push without asking the user.
- Helper: Python 3 standard library only. QML: no file over about 300 lines.
- Colors only from the `Color` singleton (`Color.foreground`, `Color.background`, `Color.accent`, `Color.urgent`, `Color.muted`, `Color.popups.*`, `Color.bar.*`, `Util.alpha(color, a)`). No hex literals in QML.
- Every animation duration goes through `Style.duration(ms)`. Spacing goes through `Style.space(px)`.
- Copy rules: English UI text, no em dashes or en dashes anywhere, no ticket numbers in names or comments.
- Settings keys: `vaultPath`, `refreshIntervalSec` (10 to 600, default 30), `syncCheckCommand` (default empty), `lists` (JSON array).
- Default lists: `read-later` folder `Read Later`, `retro` sections `Retrospective.md`, `todo` checklist `Todo.md`.
- Helper write rules: re-read before writing, match the item by its key text, write a temp file in the same folder then rename, return `changed` when the key is gone.
- Fresh window: 3.4 s. Clear arm window: 3 s. Helper timeout: 5 s.

## Review Focus

- A phone capture lands in `Todo.md` between the helper's read and its write: the capture must survive. Test: `test_done_keeps_line_added_after_read` in Task 3.
- A list path such as `../../.ssh` escapes the vault: the helper must refuse it. Test: `test_path_outside_vault_is_refused` in Task 1.
- Two todos with the same text: ticking one removes exactly one line. Test: `test_done_removes_only_first_duplicate` in Task 3.
- `lists` arrives from `shell.json` as a foreign array, or holds a bad entry: the widget keeps working and names the bad entry. Test: `normalizeSettings drops an entry without a type and reports it` in Task 5.
- The vault folder disappears (unmounted disk) while the popup is open: the last good data stays, and the header shows the error. Test: `test_read_missing_vault_reports_every_list_missing` in Task 1, and the manual check in Task 11.

## File Structure

```
manifest.json                  bar widget, settings schema, aliases
Panel.qml                      entry point: chip, KeyboardPanel, IPC
Service.qml                    runs the helper, keeps the last good payload
Model.js                       pure logic, loaded by QML and by node
KeyedListModel.qml             ListModel kept in sync by key (stable delegates)
ShelfChip.qml                  bar chip: glyph, count, ping dot, urgent dot
ShelfPopup.qml                 popup layout: header, tabs, active list, add bar, footer
TabBar.qml                     segmented tabs with the sliding indicator
FolderList.qml, FolderRow.qml
ChecklistList.qml, ChecklistRow.qml
SectionsList.qml               section columns
AddBar.qml                     text field, section picker, Add button
ClearButton.qml                two-step clear with the drain bar
SettingsView.qml               vault path, interval, sync check, list editor
bin/obsidian-shelf             helper entry point (adds helper/ to sys.path)
helper/shelf_io.py             read_text, atomic_write, resolve_in_vault
helper/shelf_folder.py         folder parsing and actions
helper/shelf_checklist.py      checklist parsing and actions
helper/shelf_sections.py       sections parsing and actions
helper/shelf_cli.py            argument parsing, dispatch, JSON output
systemd/obsidian-headless.service
tests/test_folder.py, test_checklist.py, test_sections.py, test_cli.py
tests/model.test.js
tests/qml-source-test.sh
README.md
```

Run all Python tests with: `PYTHONPATH=helper python3 -m unittest discover -s tests -v`

---

### Task 1: Helper foundation and the `folder` read

**Files:**
- Create: `helper/shelf_io.py`, `helper/shelf_folder.py`, `tests/test_folder.py`

**Interfaces:**
- Produces:
  - `shelf_io.resolve_in_vault(vault: Path, rel: str) -> Path`. Raises `shelf_io.OutsideVault` when the resolved path is not inside `vault.resolve()`.
  - `shelf_io.read_text(path: Path) -> str` (UTF-8).
  - `shelf_io.atomic_write(path: Path, text: str) -> None` (temp file in the same folder, `os.replace`).
  - `shelf_folder.read_folder(vault: Path, cfg: dict) -> dict` returning `{"id", "state", "items"}` or `{"id", "state", "message"}`. Item: `{"key", "title", "excerpt", "url", "domain", "modifiedAt"}`. `url` and `domain` are `""` when absent. `modifiedAt` is ISO 8601 with offset.

- [ ] **Step 1: Write the failing tests** in `tests/test_folder.py`. Each test builds a vault in `tempfile.TemporaryDirectory()`. Use the real ReadItLater note shape:

```python
TWEET = """[[ReadItLater]] [[Tweet]]

# [WitcherHour](https://x.com/WitcherHour/status/2107244538465231193)

> Roach noooo! [pic.twitter.com/y0nddS1RLR](https://t.co/y0nddS1RLR)
"""
CFG = {"id": "read-later", "type": "folder", "path": "Read Later"}

def test_title_url_excerpt_domain_from_readitlater_note(self):
    item = read_folder(vault, CFG)["items"][0]
    self.assertEqual(item["title"], "WitcherHour")
    self.assertEqual(item["url"], "https://x.com/WitcherHour/status/2107244538465231193")
    self.assertEqual(item["excerpt"], "Roach noooo! pic.twitter.com/y0nddS1RLR")
    self.assertEqual(item["domain"], "x.com")
    self.assertEqual(item["key"], "Read Later/Tweet from WitcherHour.md")
```

Also: `test_front_matter_url_wins_over_body` (`url: https://example.org/a` in front matter, body link elsewhere: url is the front matter one, domain `example.org`), `test_www_is_stripped_from_domain`, `test_title_falls_back_to_file_name` (no `# ` heading), `test_note_without_url_has_empty_url`, `test_excerpt_stops_at_200_characters`, `test_newest_first` (set mtimes with `os.utime`), `test_subfolders_and_non_md_files_are_ignored`, `test_missing_folder_state_missing` (`state == "missing"`, message `"Read Later not found"`), `test_path_outside_vault_is_refused` (`path: "../outside"` gives `state == "error"`, message contains `"outside the vault"`), `test_read_missing_vault_reports_every_list_missing` (vault path that does not exist: `state == "missing"`).

- [ ] **Step 2: Run the tests to see them fail**

Run: `PYTHONPATH=helper python3 -m unittest tests.test_folder -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'shelf_folder'`.

- [ ] **Step 3: Implement `shelf_io.py` and `read_folder`** per spec section 5.1. Front matter: only a leading `---` block, keys `url`, `source`, `link`. Body URL: first match of `https?://[^\s)>\]]+`. Excerpt: first body line that is not front matter, not a heading, not wikilinks only; strip a leading `> `; reduce `[text](url)` to `text`; cut at 200 characters.

- [ ] **Step 4: Run the tests to see them pass**

Run: `PYTHONPATH=helper python3 -m unittest tests.test_folder -v`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add helper tests/test_folder.py
git commit -m "feat(helper): read folder lists from the vault"
```

### Task 2: Read `checklist` and `sections`

**Files:**
- Create: `helper/shelf_checklist.py`, `helper/shelf_sections.py`, `tests/test_checklist.py`, `tests/test_sections.py`

**Interfaces:**
- Consumes: `shelf_io.resolve_in_vault`, `shelf_io.read_text` (Task 1).
- Produces:
  - `shelf_checklist.read_checklist(vault: Path, cfg: dict) -> dict`, items `{"key": <full line>, "text": <text after "- [ ] ">}`.
  - `shelf_sections.read_sections(vault: Path, cfg: dict) -> dict`, with `"sections": [{"heading": str, "items": [{"key": heading + "\n" + line, "text": str}]}]`.

- [ ] **Step 1: Write the failing tests.** Checklist: `test_reads_open_items_in_file_order`, `test_star_bullet_counts`, `test_checked_lines_are_hidden` (`- [x] a` and `- [X] b` hidden), `test_indented_items_are_ignored`, `test_missing_file_state_missing` (message `"Todo.md not found"`). Sections, on the real file:

```python
RETRO = "## Good\n\n## Bad\n- canal payments-sandbox-staging-errors\n- Meilleur logs payment-service car pas d'accès aws\n"

def test_reads_sections_and_items(self):
    out = read_sections(vault, {"id": "retro", "type": "sections", "path": "Retrospective.md"})
    self.assertEqual([s["heading"] for s in out["sections"]], ["Good", "Bad"])
    self.assertEqual(out["sections"][0]["items"], [])
    self.assertEqual(out["sections"][1]["items"][0]["key"], "Bad\n- canal payments-sandbox-staging-errors")
```

Also `test_text_before_first_heading_is_not_an_item`, `test_nested_bullets_are_not_items`, `test_heading_levels_one_to_six`.

- [ ] **Step 2: Run the tests to see them fail**

Run: `PYTHONPATH=helper python3 -m unittest tests.test_checklist tests.test_sections -v`
Expected: FAIL with `ModuleNotFoundError`.

- [ ] **Step 3: Implement both readers** per spec sections 5.2 and 5.3. Item regex for checklist: `^[-*] \[ \] (.+)$`. Heading regex: `^#{1,6} (.+)$`. Section item regex: `^[-*] (.+)$` (no leading space).

- [ ] **Step 4: Run the tests to see them pass**

Run: `PYTHONPATH=helper python3 -m unittest tests.test_checklist tests.test_sections -v`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add helper tests
git commit -m "feat(helper): read checklist and sections lists"
```

### Task 3: Write actions

**Files:**
- Modify: `helper/shelf_folder.py`, `helper/shelf_checklist.py`, `helper/shelf_sections.py`
- Test: `tests/test_folder.py`, `tests/test_checklist.py`, `tests/test_sections.py`

**Interfaces:**
- Consumes: `shelf_io.atomic_write` (Task 1).
- Produces (each returns `{"ok": True}` or `{"ok": False, "error": code, "message": str}`, codes `changed`, `missing`, `invalid`, `io`):
  - `shelf_folder.done_folder(vault, cfg, key) -> dict`
  - `shelf_checklist.done_checklist(vault, cfg, key) -> dict`, `shelf_checklist.add_checklist(vault, cfg, text) -> dict`
  - `shelf_sections.add_sections(vault, cfg, heading, text) -> dict`, `shelf_sections.clear_sections(vault, cfg) -> dict`

- [ ] **Step 1: Write the failing tests.**
  - Folder: `test_done_moves_note_to_trash` (file now at `.trash/<name>.md`), `test_done_trash_conflict_adds_suffix` (second note with the same name lands at `.trash/<stem> 1.md`), `test_done_unknown_key_returns_changed`, `test_done_key_outside_folder_is_invalid`.
  - Checklist: `test_done_delete_removes_line`, `test_done_check_mode_writes_x` (`onDone: "check"` gives `- [x] a`), `test_done_delete_purges_checked_lines` (`- [x] old` disappears on the same write), `test_done_removes_only_first_duplicate`, `test_done_keeps_line_added_after_read`:

```python
def test_done_keeps_line_added_after_read(self):
    write(vault / "Todo.md", "- [ ] a\n- [ ] b\n")
    key = read_checklist(vault, CFG)["items"][0]["key"]
    write(vault / "Todo.md", "- [ ] a\n- [ ] b\n- [ ] from phone\n")
    self.assertEqual(done_checklist(vault, CFG, key), {"ok": True})
    self.assertEqual(read(vault / "Todo.md"), "- [ ] b\n- [ ] from phone\n")
```

  - `test_add_appends_open_item` (file without final newline gets one first), `test_add_creates_missing_file`, `test_add_empty_text_is_invalid`.
  - Sections: `test_add_inserts_after_last_item_of_section` (adding "x" to Good on `RETRO` gives `## Good\n- x\n\n## Bad\n...`), `test_add_to_section_with_items_appends_after_last`, `test_add_unknown_heading_returns_changed`, `test_clear_keeps_headings_and_preamble` (result `## Good\n\n## Bad\n`), `test_clear_missing_file_returns_missing`.

- [ ] **Step 2: Run the tests to see them fail**

Run: `PYTHONPATH=helper python3 -m unittest discover -s tests -v`
Expected: the new tests FAIL with `ImportError` or `AttributeError`.

- [ ] **Step 3: Implement the actions.** Each action re-reads the file, finds the first line equal to the key's line, edits the list of lines, and calls `atomic_write`. Trash suffix: try `<stem>.md`, then `<stem> 1.md`, `<stem> 2.md`, and so on.

- [ ] **Step 4: Run the tests to see them pass**

Run: `PYTHONPATH=helper python3 -m unittest discover -s tests -v`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add helper tests
git commit -m "feat(helper): add, done and clear actions with re-read before write"
```

### Task 4: CLI entry point

**Files:**
- Create: `helper/shelf_cli.py`, `bin/obsidian-shelf` (mode 755), `tests/test_cli.py`

**Interfaces:**
- Consumes: every reader and action from Tasks 1 to 3.
- Produces: `shelf_cli.main(argv: list[str], stdin: TextIO) -> tuple[int, dict]`, and the command contract of spec section 6:
  - `read --vault V --lists JSON` gives `{"ok": true, "readAt": ISO, "lists": [...]}` in the order of the given lists.
  - `add --vault V --list JSON [--section H]`, text on stdin. `done --vault V --list JSON --item KEY`. `clear --vault V --list JSON`.
  - Exit code 0 whenever the helper ran. Exit code 2 and `{"ok": false, "error": "invalid"}` for bad arguments or bad JSON.

- [ ] **Step 1: Write the failing tests:** `test_read_returns_lists_in_given_order`, `test_add_reads_text_from_stdin`, `test_add_strips_trailing_newline_from_stdin`, `test_bad_lists_json_is_invalid_exit_2`, `test_unknown_command_is_invalid_exit_2`, `test_action_on_wrong_type_is_invalid` (`clear` on a checklist), and `test_script_runs_end_to_end` (runs `bin/obsidian-shelf read` with `subprocess.run`, parses stdout as JSON).

- [ ] **Step 2: Run the tests to see them fail**

Run: `PYTHONPATH=helper python3 -m unittest tests.test_cli -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'shelf_cli'`.

- [ ] **Step 3: Implement `shelf_cli.main` with `argparse`, and `bin/obsidian-shelf`.** The script inserts `Path(__file__).resolve().parent.parent / "helper"` into `sys.path`, calls `main(sys.argv[1:], sys.stdin)`, prints the dict with `json.dumps(..., ensure_ascii=False)`, and exits with the code.

- [ ] **Step 4: Run all Python tests**

Run: `PYTHONPATH=helper python3 -m unittest discover -s tests -v`
Expected: all PASS.

- [ ] **Step 5: Run the helper on the real vault (read only)**

Run: `bin/obsidian-shelf read --vault ~/Documents/obsidian/tmn --lists '[{"id":"read-later","name":"Read later","type":"folder","path":"Read Later"},{"id":"retro","name":"Retro","type":"sections","path":"Retrospective.md"},{"id":"todo","name":"Todo","type":"checklist","path":"Todo.md"}]' | python3 -m json.tool`
Expected: `"ok": true`, three lists in state `ok`, the WitcherHour note in `read-later`.

- [ ] **Step 6: Commit**

```bash
git add helper bin tests
git commit -m "feat(helper): obsidian-shelf command line entry point"
```

### Task 5: `Model.js`

**Files:**
- Create: `Model.js`, `tests/model.test.js`

**Interfaces:**
- Produces (exported with `if (typeof module !== "undefined") module.exports = {...}`, as in `tmn73.jira`):
  - `DEFAULT_LISTS: Array<List>` where `List = {id, name, type, path, badge, onDone}`.
  - `normalizeSettings(raw) -> {vaultPath, refreshIntervalSec, syncCheckCommand, lists, errors}`. `lists` falls back to `DEFAULT_LISTS` when the key is absent. `errors` is an array of strings, one per dropped entry.
  - `listItemCount(listPayload) -> number` (items, or the sum of section items).
  - `badgeCount(payload, lists) -> number` (only lists with `badge`, only state `ok`).
  - `itemKeys(payload) -> Array<string>`, each `listId + "\u0000" + key`.
  - `freshKeys(previousPayload, nextPayload) -> Array<string>`, empty when `previousPayload` is null.
  - `relativeAge(iso, nowMs) -> string`: `"now"` under 60 s, `"Nm"` under 60 min, `"Nh"` under 24 h, else `"Nd"`.
  - `clockText(iso) -> string`, `"HH:MM"` local time.
  - `tooltipText(payload, lists) -> string`: `"3 read later, 7 todo"` from badge lists with a count above 0, lower-case names; `"Nothing on the shelf"` when all are 0.
  - `keyedSyncPlan(currentKeys, nextKeys) -> {remove: Array<number>, insert: Array<{index, key}>}`. Remove indices are in descending order. Applying removes then inserts to `currentKeys` gives `nextKeys`.

- [ ] **Step 1: Write the failing tests**, with `process.env.TZ = 'UTC'` at the top. Required cases: `normalizeSettings uses the default lists when lists is absent`, `normalizeSettings copies a foreign array-like into a plain array` (input `{length: 1, 0: {...}}`), `normalizeSettings drops an entry without a type and reports it` (errors `["List 2 has no valid type"]`), `normalizeSettings clamps refreshIntervalSec to 10..600`, `normalizeSettings defaults badge by type`, `badgeCount ignores sections and missing lists`, `freshKeys is empty on the first read`, `freshKeys returns only new keys`, `relativeAge boundaries` (59 s "now", 60 s "1m", 3600 s "1h", 86400 s "1d"), `tooltipText lists only non-zero badge lists`, `keyedSyncPlan turns abc into acd` (remove `[1]`, insert `[{index: 2, key: "d"}]`).

- [ ] **Step 2: Run the tests to see them fail**

Run: `node --test tests/model.test.js`
Expected: FAIL with `Cannot find module '../Model.js'`.

- [ ] **Step 3: Implement `Model.js`.** No `.pragma library` line. Plain functions, then the export guard `if (typeof module !== "undefined") module.exports = {...}`, as in `~/dev/omarchy-jira/Model.js`. QML loads it with `import "Model.js" as Model`.

- [ ] **Step 4: Run the tests to see them pass**

Run: `node --test tests/model.test.js`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Model.js tests/model.test.js
git commit -m "feat(model): settings, counts, fresh keys and keyed sync plan"
```

### Task 6: Manifest, service, chip, and first install

**Files:**
- Create: `manifest.json`, `Service.qml`, `KeyedListModel.qml`, `ShelfChip.qml`, `Panel.qml`, `tests/qml-source-test.sh`

**Interfaces:**
- Consumes: `bin/obsidian-shelf` (Task 4), `Model.js` (Task 5). Shell: `Panel` (`moduleName`, `ipcTarget`, `settings`, `opened`, `open()`, `close()`, `toggle()`), `WidgetButton` (`bar`, `text`, `tooltipText`, `active`, signal `pressed(int)`), `KeyboardPanel`, `Quickshell.Io.Process` with `StdioCollector`.
- Produces:
  - `Service.qml` properties: `settings` (in), `config` (normalized), `payload` (last good, or null), `loading`, `error` (string), `fresh` (array of keys, cleared after 3.4 s), `syncHealthy` (bool), `notice` (string, cleared after 3 s), `badge` (int), `tooltip` (string). `payload.lists[i]` matches `config.lists[i]`, because the helper keeps the given order. Functions: `refresh()`, `act(action: string, listId: string, args: object)` with `args` `{item}`, `{text, section}` or `{}`, and `openUrl(url: string)`.
  - `KeyedListModel.qml`: a `ListModel` with `function sync(items: Array<object>)`. Each item has a `key`. It applies `Model.keyedSyncPlan` and updates the roles of kept rows with `set()`.
  - `ShelfChip.qml`: properties `count`, `pinging` (bool), `urgent` (bool), `bar`, `tooltipText`; signal `pressed(int)`.

- [ ] **Step 1: Write `tests/qml-source-test.sh`** in the style of `~/dev/omarchy-jira/tests/qml-source-test.sh`: qmllint every QML file (output decides, not the exit code), fail on any `#[0-9a-fA-F]{6}` in QML, fail on any QML file over 300 lines, fail on `—` or `–` in any tracked file, and check that `Panel.qml` sets `moduleName: "tmn73.obsidian"`.

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/qml-source-test.sh`
Expected: FAIL, `Panel.qml` missing.

- [ ] **Step 3: Write `manifest.json`** with `id` `tmn73.obsidian`, `name` `Obsidian Shelf`, `version` `0.1.0`, `kinds` `["bar-widget"]`, `activation` `on-demand`, `entryPoints.barWidget` `Panel.qml`, `barWidget.category` `Productivity`, `defaultSection` `right`, the aliases of spec section 3, and schema entries `vaultPath` (path), `refreshIntervalSec` (integer, 10 to 600, step 10, default 30), `syncCheckCommand` (string, default empty).

- [ ] **Step 4: Write `Service.qml`, `KeyedListModel.qml`, `ShelfChip.qml`, `Panel.qml`.**
  - Service: a `Timer` at `config.refreshIntervalSec * 1000`; `refresh()` on start, on `Panel.opened`, and after each action; one `Process` per call kind; a 5 s `Timer` kills a stuck process and sets `error` "The helper did not answer". A failed read keeps `payload`. An action result with error `changed` sets `notice` to "Changed elsewhere, reloaded". An `xdg-open` exit code other than 0 sets `notice` to "Could not open the link". `fresh` comes from `Model.freshKeys`. The sync check runs `["sh", "-c", config.syncCheckCommand]` on each refresh when the command is not empty.
  - Chip: `WidgetButton` text = glyph `""` + count (count hidden when 0, `dimmed` when 0). The ping dot is a 6 px `Rectangle` in `Color.accent` whose scale and opacity pulse 3 times while `pinging`. The urgent dot uses `Color.urgent` when `urgent`.
  - Panel: `moduleName: "tmn73.obsidian"`, chip `pinging: service.fresh.length > 0`, `urgent: !service.syncHealthy`, a `KeyboardPanel` that for now shows a placeholder `Text` with the badge count, and `IpcHandler` functions `open`, `close`, `toggle`, `refresh`.

- [ ] **Step 5: Run the source checks and validation**

Run: `bash tests/qml-source-test.sh && omarchy plugin validate .`
Expected: no FAIL line; validate prints its check marks.

- [ ] **Step 6: Commit, then install from the local repo**

```bash
git add -A && git commit -m "feat: manifest, service, chip and panel shell"
omarchy plugin add file:///home/tmn/dev/omarchy-obsidian-shelf --enable --yes
omarchy bar set tmn73.obsidian vaultPath ~/Documents/obsidian/tmn
```

- [ ] **Step 7: Check in the running shell**

Run: `qs log -p "$OMARCHY_PATH/shell" --tail 50 | grep -i -E 'obsidian|error'`
Expected: no QML error for `tmn73.obsidian`. The chip shows the glyph and the count (Read later + Todo). Ask the user to confirm it on screen.

From here on, after each commit: `omarchy plugin update tmn73.obsidian --yes`, then `omarchy-restart-shell` after QML edits.

### Task 7: Popup frame and tabs

**Files:**
- Create: `ShelfPopup.qml`, `TabBar.qml`
- Modify: `Panel.qml` (replace the placeholder with `ShelfPopup`)

**Interfaces:**
- Consumes: `Service` (Task 6).
- Produces:
  - `ShelfPopup.qml` properties `service`, `activeIndex` (int); signals `settingsRequested()`, `closeRequested()`; it hosts the active list component by type (`FolderList`, `ChecklistList`, `SectionsList`) through a `Loader`.
  - `TabBar.qml` properties `tabs` (array of `{name, count}`), `currentIndex`; signal `activated(int)`.

- [ ] **Step 1: Extend `tests/qml-source-test.sh`**: `ShelfPopup.qml` contains `"SHELF"`; `TabBar.qml` animates the indicator with `Style.duration(380)`; the popup width uses `Style.space(440)`.
- [ ] **Step 2: Run it to see it fail.** Run: `bash tests/qml-source-test.sh`. Expected: FAIL on the three new checks.
- [ ] **Step 3: Build the header** ("SHELF", sync line from `Model.clockText(payload.readAt)` or `service.error`, settings button), the tab bar (indicator `Behavior on x` with `NumberAnimation`, `Easing.OutBack`, `Style.duration(380)`), the footer key hints (Enter open, d done, Tab switch, a add), and the popup drop-in (opacity, 10 px y, scale 0.98, `Style.duration(450)`). `PanelKeyCatcher`: Tab and Shift+Tab change `activeIndex`, `a` focuses the add field, Escape closes.
- [ ] **Step 4: Run the checks.** Run: `bash tests/qml-source-test.sh && omarchy plugin validate .`. Expected: no FAIL.
- [ ] **Step 5: Commit, update, restart, look.** `git commit -am "feat(popup): header, tabs and footer"`, then update and restart the shell. Ask the user to open the popup and check the tab indicator slide against board A.

### Task 8: `folder` rows

**Files:**
- Create: `FolderList.qml`, `FolderRow.qml`

**Interfaces:**
- Consumes: `KeyedListModel.sync` (Task 6), `service.act("done", listId, {item})`, `service.openUrl(url)`, `Model.relativeAge`.
- Produces: `FolderList.qml` properties `service`, `listId`, `currentRow` (for Enter and `d`); functions `openCurrent()`, `doneCurrent()`.

- [ ] **Step 1: Extend the source checks**: `FolderList.qml` has `add:` and `remove:` transitions; `FolderRow.qml` has the text `"NEW"` and the empty-state copy "Share a link to Obsidian from your phone. It lands here."
- [ ] **Step 2: Run them to see them fail.**
- [ ] **Step 3: Build the list and the row** per spec 8.3 and board A: a 38 px glyph tile, title, domain, age, a 2-line excerpt, an open button (hidden without `url`) and a seen button. Arrival: `add` transition (y from -16, scale from 0.96, `Easing.OutBack`, 700 ms) plus a flash `ColorAnimation` from `Util.alpha(Color.accent, 0.18)` to transparent over 2.6 s when `service.fresh.indexOf(listId + "\u0000" + key) >= 0`. Seen: remove the row from the model at once (the `remove` transition slides 48 px right and fades, then `displaced` closes the gap, 400 ms total), then call `service.act`. If the action fails, the next refresh puts the row back. Empty state per spec 8.4.
- [ ] **Step 4: Run the checks.**
- [ ] **Step 5: Commit, update, restart, test with the phone.** Ask the user to share a link from the Fold and watch it arrive with the flash and the chip ping, then mark it as seen.

### Task 9: `checklist` rows and the add bar

**Files:**
- Create: `ChecklistList.qml`, `ChecklistRow.qml`, `AddBar.qml`

**Interfaces:**
- Consumes: `service.act("done" | "add", listId, args)`.
- Produces: `AddBar.qml` properties `sections` (array of heading strings, empty for a checklist), `placeholder`; signal `submitted(string text, string section)`; function `focusInput()`.

- [ ] **Step 1: Extend the source checks**: `ChecklistRow.qml` draws the check with `Style.duration(350)`; `AddBar.qml` contains a `TextField` and an "Add" button.
- [ ] **Step 2: Run them to see them fail.**
- [ ] **Step 3: Build them.** Tick: the box fills with `Color.accent`, the check path draws (350 ms), a strike line grows over the text, then the row leaves through the list `remove` transition (start the removal 450 ms after the tick). New item: same `add` transition as folder rows, no flash. Enter in the field submits; an empty field does nothing. Empty state "Nothing left."
- [ ] **Step 4: Run the checks.**
- [ ] **Step 5: Commit, update, restart, test.** Tick a todo on the PC and check `Todo.md`. Add one from the PC and check that it shows on the Fold.

### Task 10: `sections` columns and the clear button

**Files:**
- Create: `SectionsList.qml`, `ClearButton.qml`
- Modify: `AddBar.qml` (section picker)

**Interfaces:**
- Consumes: `service.act("add", listId, {text, section})`, `service.act("clear", listId, {})`.
- Produces: `ClearButton.qml` property `count`; signal `confirmed()`.

- [ ] **Step 1: Extend the source checks**: `ClearButton.qml` contains "Clear after retro", "Click again to clear" and a 3000 ms drain via `Style.duration(3000)`.
- [ ] **Step 2: Run them to see them fail.**
- [ ] **Step 3: Build them.** Columns in a grid, one per heading, with a count and a "Nothing yet" dashed box when empty. The section picker is a row of toggle buttons, one per heading, first heading selected by default. Clear: first click arms (`Color.urgent` border, drain bar shrinks over 3 s); a second click within 3 s sweeps the items out with the remove transition and calls `act("clear")`; otherwise it disarms.
- [ ] **Step 4: Run the checks.**
- [ ] **Step 5: Commit, update, restart, test.** Add a Good topic from the PC, check `Retrospective.md`, then clear and check that the headings stay.

### Task 11: Settings view and error states

**Files:**
- Create: `SettingsView.qml`
- Modify: `ShelfPopup.qml`, `Panel.qml`

**Interfaces:**
- Consumes: `Panel.setting()`, and a `setSetting(name, value)` function in `Panel.qml` written like `tmn73.jira`'s (copy the whole settings object, change one key, assign it back).
- Produces: `SettingsView.qml` properties `config`, `errors`; signal `changed(string name, var value)`.

- [ ] **Step 1: Extend the source checks**: `SettingsView.qml` reads `~/.config/obsidian/obsidian.json` through `FileView` for the vault suggestion, and has editors for `name`, `type`, `path` and `badge` per list, plus add and remove.
- [ ] **Step 2: Run them to see them fail.**
- [ ] **Step 3: Build the view and the states.** Vault not set: the popup opens on the settings view. A `missing` list: its tab shows the expected path and an "Open settings" button. `config.errors` show at the top of the settings view. `notice` ("Changed elsewhere, reloaded", "Could not open the link") shows under the header for 3 s.
- [ ] **Step 4: Run the checks and the full test suite.**

Run: `PYTHONPATH=helper python3 -m unittest discover -s tests && node --test tests/model.test.js && bash tests/qml-source-test.sh && omarchy plugin validate .`
Expected: everything passes.

- [ ] **Step 5: Manual failure check.** With the popup open, rename the vault folder for 10 s, then rename it back. Expected: the last data stays, the header shows the error, then it recovers on the next refresh.
- [ ] **Step 6: Commit, update, restart.** `git commit -am "feat(settings): settings view, missing lists and notices"`.

### Task 12: Obsidian Headless sync service

**Files:**
- Create: `systemd/obsidian-headless.service`

**Interfaces:**
- Produces: the user unit `obsidian-headless.service` and the setting `syncCheckCommand = systemctl --user is-active --quiet obsidian-headless.service`.

- [ ] **Step 1: Install the client.** Run: `bun add -g obsidian-headless && ob --version`. If `ob` fails under Bun, install it with `npm install -g obsidian-headless` on Node 24 (installed) instead. Expected: a version number.
- [ ] **Step 2: Log in.** The login is interactive: ask the user to run `! ob login`. Then `ob sync-list-remote` lists the vault.
- [ ] **Step 3: Stop the desktop client first.** Ask the user to open Obsidian on the PC, Settings, Sync, and choose "Disconnect" (per device). Do not disable the Sync core plugin: the core plugin list syncs to the phone. Then close Obsidian.
- [ ] **Step 4: Set up the vault.** Run: `ob sync-setup --vault "<name from step 2>" --path ~/Documents/obsidian/tmn`, then `ob sync --path ~/Documents/obsidian/tmn`. Expected: the sync ends without error. Compare `find ~/Documents/obsidian/tmn -type f -not -path '*/.obsidian/*' | wc -l` before and after: no file lost.
- [ ] **Step 5: Write the unit** with `ExecStart=<path of ob> sync --continuous --path %h/Documents/obsidian/tmn`, `Restart=on-failure`, `RestartSec=10`, `WantedBy=default.target`. Install it to `~/.config/systemd/user/`, then `systemctl --user daemon-reload && systemctl --user enable --now obsidian-headless.service`.
- [ ] **Step 6: Verify end to end.** With Obsidian closed on the PC, ask the user to add a todo on the Fold. Expected: it appears in `Todo.md` and in the popup within one refresh. Set `syncCheckCommand`, stop the service, and check the urgent dot on the chip; start it again.
- [ ] **Step 7: Commit.** `git add systemd && git commit -m "feat: Obsidian Headless user service for the recommended setup"`.

### Task 13: README and final pass

**Files:**
- Create: `README.md`, `LICENSE` (MIT, tmn73)

- [ ] **Step 1: Write the README**: what it does (two sentences), the three list types and their formats (spec section 5), install (`omarchy plugin add`), settings, the recommended sync setup (Task 12) and its alternatives, the phone capture setup (ReadItLater share menu, QuickAdd captures), development commands. English, STE-flavored, no dashes. Run `python3 -I ~/.claude/skills/asd-ste100/scripts/ste-lint.py README.md`; expected 0 hard violations.
- [ ] **Step 2: Walk the motion table** of spec section 8.3 with the user in the running shell, one row at a time. Fix what does not match board A.
- [ ] **Step 3: Run the full suite** (command of Task 11, Step 4). Expected: everything passes.
- [ ] **Step 4: Commit.** `git add README.md LICENSE && git commit -m "docs: README for Obsidian Shelf"`.
- [ ] **Step 5: Ask the user** whether to create the GitHub repository `tmn73/omarchy-obsidian-shelf` and push. Do nothing until they answer.
