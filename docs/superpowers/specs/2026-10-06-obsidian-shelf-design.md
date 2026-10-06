# Obsidian Shelf: design

Status: draft for review, 2026-10-06.
Plugin ID: `tmn73.obsidian`. Name: Obsidian Shelf.
Visual reference: direction A ("Shelf") on the design canvas
https://claude.ai/artifact/PbpDrQncgF6gxLfc5HRJM5

## 1. Summary

Obsidian Shelf is an Omarchy bar widget. It shows lists that live in a Markdown
vault, and it lets the user act on them from the bar without opening Obsidian.

The main flow:

1. The user captures on the phone, in Obsidian: a shared link, a todo, a retro
   topic.
2. A sync tool puts the files on the PC. The plugin does not sync.
3. The bar chip shows a count. The popup shows each list in a tab. The user
   opens links, marks them as seen, ticks todos, adds items, and clears the
   retro list.

The plugin knows list TYPES, not use cases. A list is a name, a type and a path.
The default configuration is the author's: Read later, Retro, Todo.

## 2. Goals and non-goals

Goals:

- Show three list types from a vault: `folder`, `checklist`, `sections`.
- Act on items from the popup: open, tick, add, edit, remove, clear.
- Never lose a capture that arrives from the phone during a write.
- Follow the active Omarchy theme. Use no hardcoded colors.
- Feel alive: animated arrival, removal, tick and tab change, as in direction A.

Non-goals for v1:

- Sync. The README recommends a setup, but the plugin only reads and writes
  local files.
- Adding a `folder` item from the PC (it needs a title and preview fetcher).
- Search, note body editing, or any feature of the other "Obsidian X" plugins.
- Publishing to the marketplace. The code stays generic so that a later
  release needs no rewrite.

## 3. Naming

- Name: Obsidian Shelf. The manifest `name` and `barWidget.displayName`
  can change in a later release.
- Plugin ID: `tmn73.obsidian`. The ID never changes, because an ID change breaks
  installs.
- Repository: `tmn73/omarchy-obsidian-shelf`, developed in
  `~/dev/omarchy-obsidian-shelf`.
- Manifest aliases: `obsidian`, `read later`, `reading list`, `todo`,
  `checklist`, `retro`, `retrospective`, `inbox`, `capture`, `markdown`.
- The README states that any folder of Markdown files works, not only an
  Obsidian vault.

## 4. Configuration

Omarchy settings schemas support `enum`, `string`, `integer`, `number`,
`boolean` and `path`. They have no array type. The list definitions are
therefore a JSON array in the widget settings, and the popup edits them in its
own settings view.

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `vaultPath` | path | empty | Root folder. When empty, the settings view proposes the open vault from `~/.config/obsidian/obsidian.json`, and the user accepts it. |
| `refreshIntervalSec` | integer, 10 to 600 | 30 | Time between two reads. |
| `syncCheckCommand` | string | empty | Optional shell command. Exit code 0 means "sync is healthy". Empty means "no check". |
| `lists` | JSON array | the three default lists | The tabs, in order. |

A list entry:

| Field | Required | Values | Default |
| --- | --- | --- | --- |
| `id` | yes | `[a-z0-9-]{1,32}`, unique | none |
| `name` | yes | tab label, 1 to 24 characters | none |
| `type` | yes | `folder`, `checklist`, `sections` | none |
| `path` | yes | path relative to `vaultPath` | none |
| `badge` | no | boolean | `true` for `folder` and `checklist`, `false` for `sections` |
| `onDone` | no | `delete`, `check` (checklist only) | `delete` |

The default `lists`:

```json
[
  { "id": "read-later", "name": "Read later", "type": "folder", "path": "Read Later" },
  { "id": "retro", "name": "Retro", "type": "sections", "path": "Retrospective.md" },
  { "id": "todo", "name": "Todo", "type": "checklist", "path": "Todo.md" }
]
```

`Model.js` normalizes the settings at the boundary. Arrays that come from
`shell.json` fail `Array.isArray` and have no `indexOf`, so the model copies
them into plain arrays first. The model drops an invalid entry, and the settings view
shows why.

## 5. List types

All paths are relative to `vaultPath`. A path that resolves outside the vault is
refused.

### 5.1 `folder`

Source: every `.md` file directly in the folder. The helper ignores subfolders.

One note is one item:

- Title: the `title` key of the front matter. Fallback: the text of the first
  `# ` heading, with Markdown links reduced to their text. Last fallback: the
  file name without `.md`.
- URL: the `url`, `source` or `link` key of the front matter. Fallback: the first
  `http://` or `https://` URL in the body. No URL means the item has no "open"
  action.
- Excerpt: the first body line that is not front matter, a heading or a line of
  wikilinks only. The helper removes the `> ` quote marker and the Markdown link syntax.
  The excerpt stops at 200 characters.
- Domain: the URL host without `www.`.
- Age: from the file modification time.
- Order: newest first.

Actions:

- Open: `xdg-open <url>`, so the system default browser opens it.
- Edit: write the new title in the `title` key of the front matter, and add a
  front matter block when the note has none. The body of the note does not
  change, so the heading link stays intact.
- Remove: move the note to `<vault>/.trash/`, the Obsidian trash folder.
  On a name conflict there, the helper adds a numeric suffix. Sync tools treat the move as a
  deletion, and the local copy stays recoverable.

### 5.2 `checklist`

Source: one Markdown file. An item is a line that starts with `- [ ] ` or
`* [ ] `, without indentation. The helper keeps all other lines unchanged, and
the popup does not show them.

Actions:

- Tick, with `onDone: delete`: remove the line.
- Tick, with `onDone: check`: write `[x]` in place of `[ ]`.
- Add: append `- [ ] <text>` at the end of the file.
- Edit: replace the text of the line, and keep its bullet and its box.
- Remove: remove the line, also with `onDone: check`.

Ticked lines (`[x]` or `[X]`) are never shown. With `onDone: delete`, the helper
also removes them at the next write it makes to that file. This keeps the file
clean when the user ticks items on the phone.

### 5.3 `sections`

Source: one Markdown file. A section starts at a heading line (`#` to `######`).
An item is a top-level bullet (`- ` or `* `) under a heading. The helper keeps
the text before the first heading, and the popup does not show it.

Actions:

- Add: the user picks a section, then types the text. The helper inserts
  `- <text>` after the last item of that section, before its trailing blank
  lines. This matches the QuickAdd "choose heading" capture on the phone.
- Edit: replace the text of the topic.
- Remove: remove the topic line.
- Clear: remove every item of every section. Headings, the text before the first
  heading and one blank line between sections stay.

## 6. The helper: `bin/obsidian-shelf`

One Python 3 script, standard library only. It is the only code that reads or
writes vault files. The QML never touches the vault directly.

Commands:

```
obsidian-shelf read  --vault <path> --lists <json>
obsidian-shelf add   --vault <path> --list <json> [--section <heading>]   (text on stdin)
obsidian-shelf done  --vault <path> --list <json> --item <key>
obsidian-shelf edit  --vault <path> --list <json> --item <key>              (text on stdin)
obsidian-shelf remove --vault <path> --list <json> --item <key>
obsidian-shelf clear --vault <path> --list <json>
```

The `add` and `edit` text comes on stdin. This avoids quoting problems, and it keeps the
text out of the process list.

Item keys:

- `folder`: the note path relative to the vault.
- `checklist`: the exact text of the line.
- `sections`: the heading text, a newline, then the exact text of the line.

Output is one JSON object on stdout, and the exit code is 0 when the helper ran:

```json
{ "ok": true, "readAt": "2026-10-06T07:24:00-05:00",
  "lists": [
    { "id": "read-later", "state": "ok", "items": [
      { "key": "Read Later/Tweet from WitcherHour (2026-10-06 07-22-20).md",
        "title": "WitcherHour", "excerpt": "Roach noooo!",
        "url": "https://x.com/WitcherHour/status/2107244538465231193",
        "domain": "x.com", "modifiedAt": "2026-10-06T07:22:20-05:00" } ] },
    { "id": "retro", "state": "ok", "sections": [
      { "heading": "Good", "items": [] },
      { "heading": "Bad", "items": [ { "key": "Bad\n- canal payments-sandbox-staging-errors", "text": "canal payments-sandbox-staging-errors" } ] } ] },
    { "id": "todo", "state": "missing", "message": "Todo.md not found" }
  ] }
```

List states: `ok`, `missing` (the path does not exist), `error` (unreadable).
An action that fails returns `{ "ok": false, "error": "<code>", "message": "..." }`
with one of these codes: `changed` (the item is no longer there), `missing`,
`invalid` (bad arguments), `io` (write failed).

Rules for every write:

1. Read the file again just before the write.
2. Find the item by its key (its text), never by a line number. A phone capture
   that synced in between therefore stays in the file.
3. Write to a temporary file in the same folder, then rename it over the
   original.
4. If the key is not found, write nothing and return `changed`.

## 7. Plugin structure

The plugin follows the pattern of `tmn73.jira` and `tmn73.calendar`: one
service, one pure model, small QML components. No file goes over about 300
lines.

| File | Responsibility |
| --- | --- |
| `manifest.json` | Bar widget, settings schema, aliases. |
| `Panel.qml` | Entry point: the bar chip and the popup host. |
| `Service.qml` | Runs the helper on a timer, on popup open and after each action. Exposes one model. A failed read keeps the last good data. |
| `Model.js` | Pure logic: settings normalization, badge count, fresh-item detection, tab state, relative ages. Tested under `node --test`. |
| `ShelfPopup.qml` | Popup layout: header, tab bar, active list, add bar, footer. |
| `TabBar.qml` | Segmented tabs with counts and the sliding indicator. |
| `FolderList.qml`, `FolderRow.qml` | The `folder` type. |
| `ChecklistList.qml`, `ChecklistRow.qml` | The `checklist` type. |
| `SectionsList.qml` | The `sections` type, with section columns. |
| `AddBar.qml` | The text field, the section picker and the Add button. |
| `ClearButton.qml` | The two-step clear with the 3-second drain. |
| `SettingsView.qml` | Vault path, refresh interval, sync check, list editor. |
| `bin/obsidian-shelf` | The helper (section 6). |
| `tests/` | Helper tests, model tests, QML source checks. |

Fresh items: `Model.js` compares the item keys of two reads. A key that was not
in the previous read is "fresh" for 3.4 seconds. The first read after start-up
marks nothing as fresh.

## 8. Visual and motion

The reference is direction A on the design canvas. All colors come from the
shell `Color` singleton, and all durations go through `Style.duration(ms)`, so that
the shell `reduceMotion` setting turns the animations off.

### 8.1 Bar chip (popup closed)

v1 ships the states of the "Bar chip" board. A later design pass may extend the
closed state.

| State | Look |
| --- | --- |
| Empty | Icon only, at reduced opacity. |
| Pending | Icon and the badge count. |
| Just arrived | The count enters from above, and an accent dot pings 3 times. |
| Sync stalled | A small dot in `Color.urgent` on the chip. The chip shows it only when `syncCheckCommand` has a value and the command fails. The tooltip gives the reason. |

The icon is the "Lines" glyph (three horizontal lines, the last one shorter).
The tooltip lists the count per list, for example "3 read later, 7 todo".

### 8.2 Popup

- Size: 440 px wide. Height follows the content, up to 716 px.
- Opens with a drop of 450 ms (fade, 10 px slide, scale from 0.98).
- Header: the title "SHELF" in letter-spaced capitals, a sync line ("synced
  07:22", from the last good read), and a settings button.
- Tab bar: one segment per list with its count. The accent indicator slides
  between tabs with a spring (380 ms).
- Footer: key hints. Enter opens or ticks, `e` edits, `x` removes, Tab
  switches tabs, `a` focuses the add field.
- Every row shows an edit and a remove button on hover or when it has the
  keyboard highlight. Edit turns the text into a field: Enter saves, Escape
  cancels.

### 8.3 Item motion

| Event | Motion |
| --- | --- |
| New item arrives | Slides down 16 px and scales from 0.96 (700 ms, overshoot), then a background flash in the accent color fades over 2.6 s. A "NEW" tag shows while the item is fresh. |
| Removed | Slides 48 px to the right and fades, then the row height collapses (400 ms total). |
| Edited | The row keeps its place. The text changes in place, with no motion. |
| Todo ticked | The checkbox fills and the check mark draws (350 ms). A strike line grows over the text from left to right. Then the row leaves as above. |
| Item added | Same entry as a new item, without the flash. |
| Retro cleared | First click arms the button: it takes the `Color.urgent` color and a bar drains over 3 s. A second click within 3 s sweeps every item out. No second click: the button disarms. |
| Tab change | The list fades in and rises 6 px (320 ms). |

### 8.4 Empty and error states

- `folder` empty: a check mark, "All caught up", and "Share a link to Obsidian
  from your phone. It lands here."
- `checklist` empty: "Nothing left."
- `sections` section empty: a dashed box with "Nothing yet".
- List `missing`: the expected path, and a button that opens the settings.
- Vault not set: the popup shows only the settings view.

## 9. Sync setup (outside the plugin)

The plugin reads local files. On the author's machine, the recommended setup is:

- Obsidian Headless (`obsidianmd/obsidian-headless`, `ob sync --continuous`) runs
  as a systemd user service, so the vault stays current while the Obsidian app
  does not run.
- Sync is off in the desktop app, so that only one sync client writes the
  folder.
- `syncCheckCommand` is
  `systemctl --user is-active --quiet obsidian-headless.service`.

The README documents this setup and names the alternatives (the Obsidian app
left open, Syncthing, git). The implementation plan includes the service file
and its install steps.

## 10. Error handling

- A helper failure or a timeout (5 s) keeps the last good data. The header sync
  line turns into the error message.
- A `changed` result reloads the lists and shows "Changed elsewhere, reloaded"
  for 3 s.
- A `missing` list shows its state in its own tab. The other tabs keep working.
- The helper ignores malformed lines and never rewrites them.
- `xdg-open` failure shows "Could not open the link".

## 11. Testing

- Helper: `python3 -m unittest` on temporary vaults. Each type has cases for
  parsing, every action, a missing file, malformed lines, a capture that arrives
  between read and write, a path outside the vault, and the `.trash` name
  conflict.
- Model: `node --test tests/*.test.js` for normalization, badge count, fresh
  detection and ages.
- QML: a source check script in the style of `tmn73.jira`, and
  `omarchy plugin validate .`.
- Manual: in the running shell, with the real vault and a phone capture, check
  every row of the motion table in section 8.3.

## 12. Later

- A design pass on the closed bar state.
- Adding a `folder` item from the PC (paste a URL, fetch its title).
- Marketplace release: README with previews, a `[Verify]` issue, the listing.
