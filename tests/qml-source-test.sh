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
