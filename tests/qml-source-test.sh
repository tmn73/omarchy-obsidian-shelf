#!/usr/bin/env bash
# Source-level checks on the QML.
#
# A running shell cannot be driven headlessly, so these assert what would
# otherwise only show up as a widget that looks wrong: every file parses, the
# theme is the only source of color, the files stay small, and the names the
# panel binds to still exist.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

has() {
  local file="$1" pattern="$2" label="$3"
  [[ -f "$ROOT/$file" ]] || { fail "$file is missing ($label)"; return; }
  grep -qE -- "$pattern" "$ROOT/$file" || fail "$label"
}

hasnt() {
  local file="$1" pattern="$2" label="$3"
  [[ -f "$ROOT/$file" ]] || return 0
  if grep -qE -- "$pattern" "$ROOT/$file"; then fail "$label"; fi
}

shopt -s nullglob
qml_files=("$ROOT"/*.qml)

# ---- Every QML file parses
#
# The output decides, not the exit code: qmllint stops without a word on the
# typed IPC function signatures Quickshell requires, which the shell loads.
for file in "${qml_files[@]}"; do
  output=$(qmllint "$file" 2>&1 || true)
  [[ -z $output ]] || fail "$(basename "$file"): $output"
done

# ---- The theme is the only source of color, and files stay small
for file in "${qml_files[@]}"; do
  name=$(basename "$file")
  hasnt "$name" "#[0-9a-fA-F]{6}\b" "$name contains a hex color; use the Color singleton"
  lines=$(wc -l < "$file")
  (( lines <= 300 )) || fail "$name has $lines lines (limit 300)"
done

# ---- No em dash or en dash in any tracked text
while IFS= read -r file; do
  if grep -qP "[\x{2013}\x{2014}]" "$ROOT/$file"; then
    case "$file" in docs/*|.superpowers/*) ;; *) fail "$file contains an em dash or an en dash" ;; esac
  fi
done < <(git -C "$ROOT" ls-files --cached --others --exclude-standard)

# ---- Identity and wiring
has "Panel.qml" 'moduleName: "tmn73\.obsidian"' "Panel.qml does not set moduleName tmn73.obsidian"
has "manifest.json" '"id": "tmn73\.obsidian"' "manifest.json does not declare tmn73.obsidian"

# The helper is resolved relative to the plugin, so any checkout works.
has "Service.qml" 'Qt\.resolvedUrl\("bin/obsidian-shelf"\)' "Service.qml does not resolve the helper relatively"
hasnt "Service.qml" "/home/|/usr/local/" "Service.qml contains an absolute path"

for property in config payload loading error fresh syncHealthy notice badge tooltip; do
  has "Service.qml" "property .*\b$property\b" "Service.qml no longer exposes $property"
done
for method in refresh act openUrl; do
  has "Service.qml" "function $method\(" "Service.qml no longer has $method()"
done

# New item text never travels in the process arguments.
has "Service.qml" "SHELF_TEXT" "Service.qml passes new item text in the arguments"

has "KeyedListModel.qml" "function sync\(" "KeyedListModel.qml has no sync()"
has "KeyedListModel.qml" "keyedSyncPlan" "KeyedListModel.qml does not use Model.keyedSyncPlan"

for property in count pinging urgent; do
  has "ShelfChip.qml" "property .*\b$property\b" "ShelfChip.qml no longer exposes $property"
done
has "ShelfChip.qml" "Color\.urgent" "ShelfChip.qml does not use Color.urgent for the sync dot"

# ---- Popup frame and tabs (direction A)
has "PopupHeader.qml" '"SHELF"' "PopupHeader.qml does not show the SHELF title"
has "ShelfPopup.qml" "Style\.space\(440\)" "the popup width is not Style.space(440)"
has "ShelfPopup.qml" "Style\.duration\(450\)" "the popup drop-in is not 450 ms"
has "TabBar.qml" "Style\.duration\(380\)" "the tab indicator does not slide in 380 ms"
has "TabBar.qml" "Easing\.OutBack" "the tab indicator has no spring"
has "TabBar.qml" "Flickable \\{" "long tab names overflow instead of scrolling"
has "TabBar.qml" "function ensureVisible\\(" "the active tab can stay out of view"
has "TabBar.qml" "nameWidth: nameLabel.implicitWidth" "a tab width does not come from its name"
hasnt "TabBar.qml" "width - inset \\* 2\\) / tabCount" "tabs still share the width equally and clip long names"
for method in focusAdd nextTab forward; do
  has "ShelfPopup.qml" "function $method\(" "ShelfPopup.qml has no $method()"
done
# The keys reach the active list through ShelfPopup.forward.
for method in moveHighlight activateCurrent doneCurrent editCurrent removeCurrent; do
  has "Panel.qml" "\"$method\"" "no key reaches $method() of the active list"
done
has "ShelfPopup.qml" "maxListHeight: Math.max\(Style.space\(120\), Math.min\(Style.space\(470\), availableHeight - chromeHeight\)\)" "the list height ignores the room the panel gives"
has "Panel.qml" "availableHeight: panel.fittedContentHeight" "the popup does not know the room it has"
has "Panel.qml" "PanelKeyCatcher" "Panel.qml does not catch keys"
has "Panel.qml" "ShelfPopup" "Panel.qml does not host ShelfPopup"

# ---- Shared list contract (every list type answers what ShelfPopup calls)
for property in service listConfig listPayload fontFamily contentHeightHint; do
  has "ListStateFrame.qml" "property .*\b$property\b" "ListStateFrame.qml does not expose $property"
done
for file in FolderList.qml ChecklistList.qml SectionsList.qml; do
  [[ -f "$ROOT/$file" ]] || continue
  has "$file" "^ListStateFrame \{" "$file does not build on ListStateFrame"
  for method in moveHighlight activateCurrent doneCurrent; do
    has "$file" "function $method\(" "$file has no $method()"
  done
done

# ---- Folder rows (spec 8.3)
has "ShelfListView.qml" "add: *Transition" "ShelfListView.qml has no add transition"
has "ShelfListView.qml" "remove: *Transition" "ShelfListView.qml has no remove transition"
has "ShelfListView.qml" "displaced: *Transition" "ShelfListView.qml has no displaced transition"
has "ShelfListView.qml" "Style\.duration\(700\)" "rows do not arrive in 700 ms"
has "FolderRow.qml" '"NEW"' "FolderRow.qml has no NEW tag"
has "FolderRow.qml" "Style\.duration\(2600\)" "the arrival flash does not fade over 2.6 s"
has "FolderList.qml" "Share a link to Obsidian from your phone\. It lands here\." "FolderList.qml lost the empty-state copy"
has "FolderList.qml" "All caught up" "FolderList.qml lost the empty-state title"
has "FolderList.qml" "removeKey" "FolderList.qml does not remove the row before the helper answers"

# ---- Checklist rows and the add bar (spec 8.3)
has "ChecklistRow.qml" "Style\.duration\(350\)" "the check does not draw in 350 ms"
has "ChecklistRow.qml" "signal tickRequested" "ChecklistRow.qml does not ask the list to tick"
has "ChecklistList.qml" "Nothing left\." "ChecklistList.qml lost the empty-state copy"
has "ChecklistList.qml" "removeKey" "ChecklistList.qml does not remove the row before the helper answers"
has "AddBar.qml" "TextField" "AddBar.qml has no text field"
has "AddBar.qml" '"Add"' "AddBar.qml has no Add button"
has "AddBar.qml" "signal submitted" "AddBar.qml does not report submissions"
has "AddBar.qml" "property bool inputFocused" "AddBar.qml does not report input focus"
has "ShelfPopup.qml" "AddBar" "ShelfPopup.qml does not host the add bar"

# ---- Sections columns and the clear button (spec 8.3, 8.4)
has "ClearButton.qml" "Clear after %1" "ClearButton.qml lost the clear label"
has "ClearButton.qml" "Click again to clear %1 items" "ClearButton.qml lost the armed label"
has "ClearButton.qml" "Style\.duration\(3000\)" "the clear button does not drain over 3 s"
has "ClearButton.qml" "signal confirmed" "ClearButton.qml does not report the confirmation"
has "SectionsList.qml" "Nothing yet" "SectionsList.qml lost the empty-section copy"
has "SectionsList.qml" "ClearButton" "SectionsList.qml has no clear button"
has "SectionsList.qml" "\"clear\"" "SectionsList.qml never asks the helper to clear"
has "DashedBox.qml" "DashLine" "DashedBox.qml does not draw a dashed border"

# ---- Settings view and error states (spec 4, 8.4, 10)
has "SettingsView.qml" "signal settingChanged" "SettingsView.qml does not report changes"
has "SettingsView.qml" "Add a list" "SettingsView.qml cannot add a list"
has "SettingsView.qml" "config\.errors" "SettingsView.qml does not show settings errors"
has "ListStateFrame.qml" "Open settings" "a missing list does not offer the settings"
has "ShelfPopup.qml" "SettingsView" "ShelfPopup.qml does not host the settings view"
has "Panel.qml" "popup\.inputFocused" "the key catcher ignores focused fields"

# ---- Edit and remove on every list
has "Service.qml" 'action === "edit"' "Service.qml cannot send an edit"
has "Service.qml" 'action === "remove"' "Service.qml cannot send a remove"
has "KeyedListModel.qml" "function replaceKey\(" "KeyedListModel.qml cannot update a row in place"
has "InlineEditor.qml" "signal saved" "InlineEditor.qml does not report a save"
has "InlineEditor.qml" "signal cancelled" "InlineEditor.qml does not report a cancel"
has "InlineEditor.qml" "Escape" "InlineEditor.qml does not cancel on Escape"
for file in FolderRow.qml ChecklistRow.qml TopicCard.qml; do
  has "$file" "InlineEditor" "$file cannot edit in place"
  has "$file" "signal removeRequested" "$file cannot ask for a removal"
  has "$file" "function startEdit\(" "$file has no startEdit()"
done
for file in FolderList.qml ChecklistList.qml SectionsList.qml; do
  for method in editCurrent removeCurrent; do
    has "$file" "function $method\(" "$file has no $method()"
  done
done
has "Panel.qml" 'key === "e"' "the e key does not edit"
has "Panel.qml" 'key === "x"' "the x key does not remove"
has "ListStateFrame.qml" "property bool editing" "lists do not report an open editor"

# ---- Obsidian Sync guide
has "SyncGuide.qml" '"sync-state"' "SyncGuide.qml does not ask the helper for the sync state"
has "SyncGuide.qml" '"sync-service"' "SyncGuide.qml cannot start the background sync"
has "SyncGuide.qml" "omarchy-launch-floating-terminal-with-presentation" "SyncGuide.qml does not open setup steps in a terminal"
has "SyncGuide.qml" "function runSyncStep\(" "SyncGuide.qml has no runSyncStep()"
has "SyncGuide.qml" "obsidian-shelf-login" "SyncGuide.qml does not use the login script"
has "SyncGuide.qml" "obsidian-shelf-link" "SyncGuide.qml does not use the link script"
has "SyncCard.qml" "Obsidian Sync on this PC" "SyncCard.qml lost its title"
has "SyncCard.qml" "Pause Sync in the Obsidian app" "SyncCard.qml does not warn about the desktop client"
has "ShelfPopup.qml" "SyncCard" "ShelfPopup.qml does not show the sync card"
has "manifest.json" '"obsidianSync"' "manifest.json has no obsidianSync setting"

# ---- Unseen items stay marked until the popup has been opened
has "Service.qml" "property var unseen" "Service.qml does not keep unseen items"
has "Service.qml" "function clearUnseen\\(" "Service.qml cannot clear unseen items"
has "Service.qml" "SeenState \\{" "Service.qml does not share what was seen across screens"
has "SeenState.qml" "watchChanges: true" "SeenState.qml does not watch the seen file of the other screens"
has "SeenState.qml" "\"seen\", \"--lists\"" "SeenState.qml never stores what was seen"
has "ShelfChip.qml" "property bool marked" "ShelfChip.qml has no persistent dot"
has "Panel.qml" "clearUnseen" "Panel.qml never clears unseen items"
has "Panel.qml" "count: shelf.badge$" "the chip does not show the total of the notify lists"
has "Panel.qml" "marked: shelf.unseenBadge > 0" "the chip dot does not mark new items"
has "ListStateFrame.qml" "property int openCount" "lists cannot replay the arrival flash on open"
has "FolderRow.qml" "onReplayChanged" "FolderRow.qml does not replay its flash when the popup opens"

# ---- Thumbnails
has "Thumbnail.qml" "ClippingRectangle" "Thumbnail.qml does not round the picture"
has "Thumbnail.qml" "asynchronous: true" "Thumbnail.qml loads pictures on the UI thread"
has "Thumbnail.qml" "Image.Ready" "Thumbnail.qml does not fall back while the picture loads or fails"
has "FolderRow.qml" "Thumbnail" "FolderRow.qml shows no thumbnail"
has "FolderList.qml" "required image" "FolderList.qml does not pass the image to the row"

# ---- Tweet previews
has "Service.qml" '"enrich"' "Service.qml never asks the helper for tweet previews"
has "Service.qml" "previewsPending" "Service.qml asks for previews without checking what is pending"
has "Service.qml" "previewArgument" "Service.qml does not pass the preview kinds to the helper"
has "Thumbnail.qml" "property bool round" "Thumbnail.qml cannot draw a round avatar"
has "FolderRow.qml" "property string avatar" "FolderRow.qml has no avatar"
has "FolderList.qml" "required avatar" "FolderList.qml does not pass the avatar to the row"

# ---- Settings page (board 1)
has "HelperCall.qml" "function run\\(" "HelperCall.qml has no run()"
has "VaultPicker.qml" '"paths"' "VaultPicker.qml does not list the vault paths"
has "VaultPicker.qml" "signal picked" "VaultPicker.qml does not report the pick"
has "VaultPicker.qml" "New folder|New file" "VaultPicker.qml cannot offer a new path"
has "ListRow.qml" "Notify" "ListRow.qml has no Notify switch"
has "ListRowBody.qml" "Change" "ListRowBody.qml has no Change button"
has "ListRowBody.qml" "Add from your phone: how" "ListRowBody.qml has no phone how-to"
has "ListRowBody.qml" "Remove from shelf" "ListRowBody.qml cannot remove a list"
has "UndoToast.qml" "Undo" "UndoToast.qml has no Undo"
has "SettingsView.qml" "Model\\.moveList" "SettingsView.qml does not reorder lists"
has "SettingsView.qml" "Model\\.removeList" "SettingsView.qml does not remove lists through the model"
has "SettingsView.qml" "UndoToast" "SettingsView.qml offers no undo"
has "SettingsView.qml" "\"trash\", \"--vault\"" "removing a list never offers to delete its file"
has "UndoToast.qml" "signal action\\(\\)" "UndoToast.qml has no second action"
has "SettingsView.qml" "stays in the vault" "SettingsView.qml does not say the file stays"
has "VaultCard.qml" '"vaults"' "VaultCard.qml does not list the known vaults"

# ---- Add a list (board 2)
has "AddListSheet.qml" "Links to read or watch" "AddListSheet.qml lost the links kind"
has "AddListSheet.qml" "A checklist" "AddListSheet.qml lost the checklist kind"
has "AddListSheet.qml" "Notes by section" "AddListSheet.qml lost the sections kind"
has "AddListSheet.qml" '"scan"' "AddListSheet.qml does not suggest lists found in the vault"
has "AddListSheet.qml" '"create"' "AddListSheet.qml does not create the folder or file"
has "AddListSheet.qml" "Model\\.newListId" "AddListSheet.qml does not make a unique id"
has "AddListSheet.qml" "signal added" "AddListSheet.qml does not report the new list"
has "AddListSheet.qml" "is on the shelf" "AddListSheet.qml has no done screen"
has "ShelfPopup.qml" "AddListSheet" "ShelfPopup.qml does not open the add sheet"

# ---- A new user's first open
has "EmptyShelf.qml" "Where are your notes" "EmptyShelf.qml does not ask for the vault"
has "EmptyShelf.qml" '"vaults"' "EmptyShelf.qml does not offer the vaults Obsidian knows"
has "EmptyShelf.qml" "Add your first list" "EmptyShelf.qml does not lead to the first list"
has "ShelfPopup.qml" "EmptyShelf" "ShelfPopup.qml does not show the empty shelf"
hasnt "Panel.qml" "showSettings = !shelf.configured" "a new user still lands on the settings page"

# ---- A list's file is gone
has "ListStateFrame.qml" "Create it again" "a missing list cannot be created again"
has "ListStateFrame.qml" "signal createRequested" "ListStateFrame.qml does not ask for the file"
has "ShelfPopup.qml" "createRequested" "ShelfPopup.qml ignores a request to create a missing file"

# Every animation respects the shell's reduce-motion switch.
for file in "${qml_files[@]}"; do
  name=$(basename "$file")
  if grep -qE "duration: *[0-9]" "$file"; then
    fail "$name has a raw animation duration; use Style.duration(ms)"
  fi
done

# Boards
has "ShelfPopup.qml" 'board: "BoardList.qml"' "the popup cannot show a board"
has "BoardList.qml" "model: root.laneKeys" "a read rebuilds every lane and closes open editors"
has "BoardList.qml" "readonly property bool typing" "the popup keys fire while the date panel has focus"
has "ShelfPopup.qml" "listLoader.item.typing === true" "the popup ignores a list that is typing"
has "Service.qml" 'action === "move" \|\| action === "date"' "the service cannot move or date a card"
has "Reminders.qml" '"remind", "--vault"' "nothing asks the helper for reminders"
has "Panel.qml" "late: shelf.lateCount > 0" "a late card does not show on the chip"
has "Panel.qml" 'popup.forward\("moveCard", dx\)' "Left and Right do not move a card"
has "DatePanel.qml" "dateField.forceActiveFocus" "Escape cannot close the date panel"
hasnt "BoardLane.qml" "required property string key" "a card delegate hides the key of CardRow, so every card edits at once"
has "CardRow.qml" "root.board.toggleStatus" "a card has no status button"
has "Service.qml" "action === \"lane\"" "the service cannot add a status"
hasnt "CardRow.qml" "Move to the lane before" "the card still shows arrows instead of its status"
hasnt "CardRow.qml" "anchors.right: actions.left" "the hidden card buttons still take the width of the text"
has "CardRow.qml" "label: qsTr\(\"Remove\"\); danger: true" "removing a card does not read as a delete"
has "HoverActions.qml" "danger: true" "removing an item does not read as a delete"
has "StatusMenu.qml" "Board.statusMatches" "the status menu cannot filter or create"
has "CardRow.qml" "id: textClip" "the text shows under the card buttons on hover"
has "FolderRow.qml" "Util.alpha\(Color.popups.text, 0.03\)" "link rows run together without a card each"
has "FolderRow.qml" "titleMetrics.advanceWidth" "the link title shrinks on each layout (elided implicitWidth)"
has "ChecklistRow.qml" "Util.alpha\(Color.popups.text, 0.03\)" "checklist rows run together without a card each"
hasnt "CardRow.qml" "Qt.tint" "the card paints a color that does not follow the theme"
has "BoardList.qml" "StatusMenu \\{" "the status menu does not float at the board level"
hasnt "CardRow.qml" "StatusPanel" "the status still opens as a row under the card"

# Syntax: qmllint, when the machine has it, parses every file. It refuses the
# typed functions an IpcHandler needs, so files with one are left out.
if command -v qmllint >/dev/null 2>&1; then
  for file in "$ROOT"/*.qml; do
    grep -q "IpcHandler {" "$file" && continue
    qmllint "$file" >/dev/null 2>&1 || fail "$(basename "$file") does not parse (qmllint)"
  done
fi

if (( failures > 0 )); then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "qml source checks passed"
