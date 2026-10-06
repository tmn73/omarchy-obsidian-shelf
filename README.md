# Obsidian Shelf

Obsidian Shelf puts lists from your Obsidian vault in the Omarchy bar. You
capture links, todos and retro topics on your phone, and you handle them from
the desktop without opening Obsidian.

The plugin reads plain Markdown files, so any folder of Markdown files works.

## Install

```bash
omarchy plugin add https://github.com/tmn73/omarchy-obsidian-shelf.git --enable
```

Click the chip in the bar. The first time, the popup opens on its settings: set
the vault folder, or accept the vault open in Obsidian.

## The three list types

A list is a tab in the popup. It has a name, a type and a path in the vault.

| Type | What it reads | One item is | Actions |
| --- | --- | --- | --- |
| `folder` | every `.md` file directly in a folder | one note | open its link, mark it as seen |
| `checklist` | one file | one `- [ ] text` line | tick, add |
| `sections` | one file | one `- text` bullet under a heading | add under a heading, clear all |

Details:

- `folder`: the title comes from the first `# ` heading, else from the file
  name. The link is the `url`, `source` or `link` key of the front matter, else
  the first web address in the note. "Seen" moves the note to the `.trash`
  folder of the vault, the Obsidian trash, so you can get it back.
- `checklist`: a tick removes the line. Set `onDone` to `check` to write `[x]`
  instead. Lines ticked on the phone (`- [x]`) do not show, and the plugin
  removes them at its next write to the file.
- `sections`: a section starts at a heading (`#` to `######`). Clear removes
  every bullet and keeps the headings.

The plugin ignores lines that do not match these formats, and it never
rewrites them.

The default lists:

```json
[
  { "id": "read-later", "name": "Read later", "type": "folder", "path": "Read Later" },
  { "id": "retro", "name": "Retro", "type": "sections", "path": "Retrospective.md" },
  { "id": "todo", "name": "Todo", "type": "checklist", "path": "Todo.md" }
]
```

## Settings

Open them with the gear in the popup.

| Setting | Default | Meaning |
| --- | --- | --- |
| Vault folder | empty | The root folder of your lists. |
| Refresh every | 30 s | Time between two reads, from 10 to 600 seconds. |
| Sync check command | empty | A shell command that exits 0 while your sync works. When it fails, the chip shows a dot in the urgent color. |
| Lists | the three above | Name, type, path, and whether the list counts in the bar. |

## Keys

| Key | Action |
| --- | --- |
| Tab, Shift+Tab | next or previous list |
| Up, Down | move in the list |
| Enter | open the link, or tick the todo |
| `d`, `Del` | mark as seen, or tick |
| `a` | go to the add field |
| `r` | read the vault again |
| Escape | close |

## Capture on the phone

Obsidian on the phone writes the files, and your sync tool brings them to the
desktop.

- Links: install the ReadItLater community plugin in Obsidian and set its inbox
  folder to the path of your `folder` list. In any app, share a link to
  Obsidian, then choose ReadItLater.
- Todos and retro topics: install the QuickAdd community plugin. Make one
  Capture choice per file: append `- [ ] {{VALUE}}` to the todo file, and for
  the retro file use "Choose heading when capturing" with `- {{VALUE}}`. Set the
  Obsidian mobile pull-down action to "QuickAdd: Run".

## Sync without the Obsidian app

The plugin reads local files. If you use Obsidian Sync, the files on the
desktop change only while a sync client runs. Obsidian Headless is the official
client that runs without the app:

```bash
bun add -g obsidian-headless      # or: npm install -g obsidian-headless (Node 22+)
ob login
ob sync-setup --vault "<your vault>" --path ~/Documents/obsidian/<vault>
```

Then disconnect Sync in the desktop app (Settings, Sync, Disconnect), so that
only one client writes the folder. Do not turn off the Sync core plugin: the
list of core plugins syncs to your other devices.

Install the service from `systemd/obsidian-headless.service`. Change the vault
path in `ExecStart` first.

```bash
cp systemd/obsidian-headless.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now obsidian-headless.service
```

Then set the sync check command to
`systemctl --user is-active --quiet obsidian-headless.service`.

Other setups also work: Obsidian left open on the desktop, Syncthing, or git.

## Development

```bash
bash tests/run-all.sh
```

This runs the helper tests (`python3 -m unittest`), the model tests
(`node --test`), the QML source checks and `omarchy plugin validate`.

- `bin/obsidian-shelf` and `helper/`: the only code that reads or writes the
  vault. Python standard library only.
- `Model.js`: pure logic, tested under node.
- `Service.qml`: runs the helper and keeps the last good data.
- The other QML files: the chip, the popup and one component per list type.

Install your local copy, then update it after each commit:

```bash
omarchy plugin add file://$PWD --enable --yes
omarchy plugin update tmn73.obsidian --yes
```

## License

MIT
