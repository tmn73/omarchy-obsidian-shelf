# Obsidian Shelf: boards, dates and reminders

Status: approved in conversation on 2026-10-06. Design canvas, layout A:
https://claude.ai/artifact/3nzQrjeecDnotH2diiCHpk

## 1. Goal

A fourth list type, `board`, shows an Obsidian Kanban plugin board in the
bar. The user moves cards between columns, gives them a date and a time, and
gets an Omarchy notification when a card is due. The phone shows the same
board in the Kanban plugin, because both sides read and write the same file.

## 2. The file

The shelf reads and writes the format of the Obsidian Kanban plugin (2.0):

```markdown
---
kanban-plugin: board
---

## To do

- [ ] Reply to the landlord @{2026-10-03}

## In progress

- [ ] Draft the Q4 slides @{2026-10-06} @@{14:00}
	An indented line belongs to the card above.

## Done

**Complete**
- [x] Pay the internet bill

%% kanban:settings
```
{"kanban-plugin":"board"}
```
%%
```

Rules:

- A file is a board when its front matter has the key `kanban-plugin`.
- A column (lane) starts at a `## ` heading. A trailing ` (n)` on the title
  is the plugin's card limit; the shelf shows the title without it.
- A lane is the Complete lane when its first line that is not blank is
  `**Complete**`.
- A card is a line `- [ ] text` or `- [x] text` at the start of a line in a
  lane. The lines after it that start with a space or a tab belong to it, and
  move with it.
- The board ends at `***` (the plugin's archive follows) or at
  `%% kanban:settings`. The shelf never reads or changes what follows.
- A date is `@{YYYY-MM-DD}` and a time is `@@{HH:mm}`, at the end of the card
  line. The triggers `@` and `@@` come from the settings block when it names
  `date-trigger` or `time-trigger`. When the block names a `date-format`
  other than `YYYY-MM-DD`, the shelf shows dates as written and turns date
  editing and reminders off for that board.
- The identity of a card (its key) is its text without the date and the
  time. The second card with the same text gets the key `text #2`, and so on.
  Moving a card or changing its date keeps its key, so it never shows as new.
- Every write reads the file again first and finds the card by its key. A
  card that is gone answers `changed`, like the other list types.

## 3. Actions

| Action | Effect on the file |
| --- | --- |
| Add to a lane | `- [ ] text` after the last card of the lane, or after its heading (and `**Complete**`). |
| Tick | The card moves to the end of the Complete lane as `- [x]`. A board without a Complete lane marks the card `[x]` where it is. |
| Tick a done card | The card moves to the end of the first lane as `- [ ]`. |
| Move left or right | The card moves to the end of the lane before or after it, in file order. Into the Complete lane it becomes `[x]`; out of it, `[ ]`. |
| Set the date | Replaces or adds `@{date}` and, when given, `@@{time}`. No date clears both. A time without a date takes today. |
| Edit | Replaces the text; the checkbox, the date and the time stay. |
| Remove | Deletes the card and its indented lines. |
| Clear Done | Deletes every card of the Complete lanes. Headings and the `**Complete**` line stay. |

## 4. The board tab (layout A)

- The lanes stack. The open lanes show from the one closest to Done to the
  first one, so "In progress" comes before "To do". The Complete lanes come
  last, folded, with their count, a show or hide toggle and Clear.
- In an open lane, dated cards come first, oldest date on top, then by time;
  cards without a date follow in file order.
- A card shows its checkbox, its text and a date chip:
  - before today: "3 days late", in `Color.urgent`;
  - today: "Today" or "Today 14:00", in `Color.accent`;
  - tomorrow: "Tomorrow" plus the time;
  - later: "Mon 20 Oct" plus the time.
  Done cards show no chip.
- On hover or under the keyboard highlight a card shows: its status (the
  lane name), date, edit and remove. The status opens a menu that floats
  under the button, over the cards below (above it when there is no room).
  A "Move to…" field filters the lanes; a name that is not a lane yet
  becomes "+ Create", which adds a `## ` lane before the Complete lane (or
  at the end) and moves the card there. Enter takes the highlighted line,
  Up and Down move the highlight, Escape closes, and a scroll closes it. The date button opens a small panel under the
  card: Today, Tomorrow, Next Monday, In a week, a date field, a time field
  and No date. It says that a card with a time rings at that time and a
  card with only a date rings in the morning summary.
- The add bar picks the lane, like the heading picker of the notes lists. It
  offers the open lanes; the first is the default.
- Keys: Enter ticks, Left and Right move (the popup key catcher gives no
  modifiers, and Left and Right have no other use in a list), `t` opens the
  date panel, `e` edits, `x` removes, `a` adds.
- The tab count and the chip count the cards of the open lanes.

## 5. Reminders

- The helper sends them, so one notification goes out even with a bar on
  every screen. Each bar runs `remind` every 60 seconds and once at start.
  The helper holds a lock and keeps what it sent in
  `$XDG_STATE_HOME/obsidian-shelf/reminders.json`.
- A card in an open lane with a date and a time rings once, at that time.
  When the PC was off at that time, it rings at the first run later that same
  day. It never rings on a later day: the morning summary lists it as late.
- The morning summary rings once a day, at the first run after the summary
  time (setting `reminderTime`, default `09:00`). It names the cards with a
  date and no time that are due today, and every late card. A day with
  nothing due and nothing late sends nothing.
- A notification uses `omarchy-notification-send`, with the shelf as the
  app name and a click that runs `omarchy-shell tmn73.obsidian open`. Without
  that command it uses `notify-send`.
- Each board list has a "Remind me" setting (`remind`, default on).

## 6. The chip

The count is the cards and items that wait in the Notify lists (unchanged).
The count turns `Color.urgent` while a card of a Notify board is late. The
red dot stays for a sync that stopped.

## 7. Settings

- "Add a list" offers a fourth kind, "A board". It creates the file with the
  plugin's front matter, the lanes typed as chips (To do, In progress, Done)
  and `**Complete**` under the last lane. The vault scan suggests the files
  that are already boards.
- The settings row of a board shows the lanes note, the "Remind me" toggle
  and the phone how-to for the Kanban plugin. It has no "When ticked" choice.

## 8. Out of scope

Dragging cards, reordering cards inside a lane, card tags, links and
sub-tasks, the plugin's archive, lanes with a date format other than
`YYYY-MM-DD`, recurring cards, and reminders on the phone.

## 9. Tests

The helper parse and every action are unit tests with real files, the
reminders take an injected clock and an injected sender, and the model
orders lanes and labels dates under node. The QML keeps source checks and a
live test with the user.
