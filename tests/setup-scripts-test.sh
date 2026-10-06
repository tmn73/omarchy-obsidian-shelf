#!/usr/bin/env bash
# The interactive sync setup steps, driven by a fake `ob` client.
#
# The fake reads its exit codes, one per call, from a file, so each case
# scripts a sequence: a wrong password (2), a Ctrl+C (1), then a success (0).
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

cat > "$WORK/ob" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$OB_CALLS"
code=$(head -n 1 "$OB_CODES")
sed -i '1d' "$OB_CODES"
echo "stack trace noise" >&2
exit "${code:-0}"
EOF
chmod 755 "$WORK/ob"
export OB_CALLS="$WORK/calls" OB_CODES="$WORK/codes"

run() {
  # run <script> <codes...>: prints output, sets $status
  local script=$1; shift
  printf '%s\n' "$@" > "$OB_CODES"
  : > "$OB_CALLS"
  output=$(printf 'My Vault\nMy Vault\nMy Vault\n' | "$ROOT/bin/$script" "$WORK/ob" "$WORK/vault dir" 2>&1)
  status=$?
}

# ---- login
run obsidian-shelf-login 2 0
[[ $status -eq 0 ]] || fail "login: a success after one wrong password should exit 0, got $status"
[[ $output == *"Try 2 of 3"* ]] || fail "login: no retry message after a wrong password"
[[ $output != *"stack trace noise"* ]] || fail "login: the client's error trace leaks to the user"
[[ $(wc -l < "$OB_CALLS") -eq 2 ]] || fail "login: expected 2 client calls"

run obsidian-shelf-login 2 2 2
[[ $status -eq 1 ]] || fail "login: three wrong passwords should exit 1, got $status"
[[ $output == *"https://obsidian.md/account"* ]] || fail "login: no password reset hint after three failures"

run obsidian-shelf-login 1
[[ $status -eq 130 ]] || fail "login: Ctrl+C should stop at once with 130, got $status"
[[ $(wc -l < "$OB_CALLS") -eq 1 ]] || fail "login: Ctrl+C should not retry"

# ---- link
run obsidian-shelf-link 0 3 0 0
[[ $status -eq 0 ]] || fail "link: a success on the second name should exit 0, got $status"
[[ $output == *"Try 2 of 3"* ]] || fail "link: no retry message after a wrong vault name"
grep -q -- "--path $WORK/vault dir" "$OB_CALLS" || fail "link: sync-setup did not get the vault path"
grep -q -- "--vault My Vault" "$OB_CALLS" || fail "link: sync-setup did not get the typed vault name"

if (( failures > 0 )); then
  echo "$failures setup script check(s) failed" >&2
  exit 1
fi
echo "setup script checks passed"
