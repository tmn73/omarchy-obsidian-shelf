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
if [[ $1 == sync-list-remote ]]; then cat "$OB_REMOTE"; exit 0; fi
code=$(head -n 1 "$OB_CODES")
sed -i '1d' "$OB_CODES"
echo "stack trace noise" >&2
exit "${code:-0}"
EOF
chmod 755 "$WORK/ob"
export OB_CALLS="$WORK/calls" OB_CODES="$WORK/codes" OB_REMOTE="$WORK/remote"
ONE='{"vaults":[{"id":"v1","name":"Sam'"'"'s Vault","region":"North America"}],"shared":[]}'
TWO='{"vaults":[{"id":"v1","name":"Work","region":"Europe"},{"id":"v2","name":"Home","region":"Europe"}],"shared":[]}'
NONE='{"vaults":[],"shared":[]}'


run() {
  # run <script> <answers> <codes...>: prints output, sets $status
  local script=$1 answers=$2; shift 2
  printf '%s\n' "$@" > "$OB_CODES"
  : > "$OB_CALLS"
  output=$(printf "$answers" | "$ROOT/bin/$script" "$WORK/ob" "$WORK/vault dir" 2>&1)
  status=$?
}

# ---- login
run obsidian-shelf-login '' 2 0
[[ $status -eq 0 ]] || fail "login: a success after one wrong password should exit 0, got $status"
[[ $output == *"Try 2 of 3"* ]] || fail "login: no retry message after a wrong password"
[[ $output != *"stack trace noise"* ]] || fail "login: the client's error trace leaks to the user"
[[ $(wc -l < "$OB_CALLS") -eq 2 ]] || fail "login: expected 2 client calls"

run obsidian-shelf-login '' 2 2 2
[[ $status -eq 1 ]] || fail "login: three wrong passwords should exit 1, got $status"
[[ $output == *"https://obsidian.md/account"* ]] || fail "login: no password reset hint after three failures"

run obsidian-shelf-login '' 1
[[ $status -eq 130 ]] || fail "login: Ctrl+C should stop at once with 130, got $status"
[[ $(wc -l < "$OB_CALLS") -eq 1 ]] || fail "login: Ctrl+C should not retry"

# ---- link
echo "$ONE" > "$OB_REMOTE"
run obsidian-shelf-link 'y\n' 0
[[ $status -eq 0 ]] || fail "link: confirming the only vault should exit 0, got $status"
[[ $output == *"Sam's Vault"* ]] || fail "link: the only vault is not named in the question"
grep -q -- "sync-setup --vault v1 --path $WORK/vault dir" "$OB_CALLS" || fail "link: sync-setup did not get the vault id and the folder"

run obsidian-shelf-link 'n\n' 0
[[ $status -eq 130 ]] || fail "link: answering no should stop with 130, got $status"
grep -q -- "sync-setup" "$OB_CALLS" && fail "link: answering no still ran sync-setup"

echo "$TWO" > "$OB_REMOTE"
run obsidian-shelf-link '2\n' 0
[[ $status -eq 0 ]] || fail "link: picking vault 2 should exit 0, got $status"
[[ $output == *"1) Work"* && $output == *"2) Home"* ]] || fail "link: no numbered menu for two vaults"
grep -q -- "sync-setup --vault v2 " "$OB_CALLS" || fail "link: picking 2 did not link the second vault"

run obsidian-shelf-link '9\n1\n' 0
grep -q -- "sync-setup --vault v1 " "$OB_CALLS" || fail "link: a wrong number did not ask again"

echo "$NONE" > "$OB_REMOTE"
run obsidian-shelf-link '' 0
[[ $status -eq 1 ]] || fail "link: no remote vault should exit 1, got $status"
[[ $output == *"No remote vault"* ]] || fail "link: no message when the account has no vault"

echo "$ONE" > "$OB_REMOTE"
run obsidian-shelf-link 'y\ny\n' 3 0
[[ $status -eq 0 ]] || fail "link: a retry after a failed setup should exit 0, got $status"
[[ $output == *"Try 2 of 3"* ]] || fail "link: no retry message after a failed setup"

if (( failures > 0 )); then
  echo "$failures setup script check(s) failed" >&2
  exit 1
fi
echo "setup script checks passed"
