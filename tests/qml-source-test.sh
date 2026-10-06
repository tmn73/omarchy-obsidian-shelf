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
for method in moveHighlight activateCurrent doneCurrent focusAdd nextTab; do
  has "ShelfPopup.qml" "function $method\(" "ShelfPopup.qml has no $method()"
done
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
has "SettingsView.qml" "obsidian/obsidian\.json" "SettingsView.qml does not propose the open vault"
has "SettingsView.qml" "FileView" "SettingsView.qml does not read the vault registry with FileView"
has "SettingsView.qml" "signal settingChanged" "SettingsView.qml does not report changes"
has "SettingsView.qml" "Add list" "SettingsView.qml cannot add a list"
has "SettingsView.qml" "config\.errors" "SettingsView.qml does not show settings errors"
for field in name type path badge; do
  has "ListEditorRow.qml" "\b$field\b" "ListEditorRow.qml does not edit $field"
done
has "ListEditorRow.qml" "signal removed" "ListEditorRow.qml cannot remove a list"
has "ListStateFrame.qml" "Open settings" "a missing list does not offer the settings"
has "ShelfPopup.qml" "SettingsView" "ShelfPopup.qml does not host the settings view"
has "Panel.qml" "popup\.inputFocused" "the key catcher ignores focused fields"

# Every animation respects the shell's reduce-motion switch.
for file in "${qml_files[@]}"; do
  name=$(basename "$file")
  if grep -qE "duration: *[0-9]" "$file"; then
    fail "$name has a raw animation duration; use Style.duration(ms)"
  fi
done

if (( failures > 0 )); then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "qml source checks passed"
