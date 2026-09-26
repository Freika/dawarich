#!/bin/sh
set -u
root="$(cd "$(dirname "$0")/../../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/sp-pr-checks.XXXXXX")"
repo="$scratch/repo"
counterparts=.github/workflows/ecto-counterparts.yml
nightly=.github/workflows/ecto-nightly.yml
failures=0

pass() { echo "ok - $1"; }
flunk() { echo "not ok - $1"; failures=$((failures + 1)); }
verdict() { if [ "$1" -eq 0 ]; then pass "$2"; else flunk "$2"; fi; }

trap 'rm -rf "$scratch"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

g() {
  git -C "$repo" -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"
}

mkdir -p "$repo/db" "$repo/scripts/schema_parity" "$repo/.github/workflows"
cp "$root/db/release_migrations.json" "$repo/db/"
cp "$root/scripts/schema_parity/pr_checks.rb" "$root/scripts/schema_parity/inventory_tags.rb" "$repo/scripts/schema_parity/"
cp "$root/$counterparts" "$root/$nightly" "$repo/.github/workflows/"
cp -R "$repo" "$scratch/orig"
printf '%s\n' fresh step:1.15.2 rows:1.15.2 upgrade:0.37.2 refused:0.0.8 > "$scratch/list.txt"
full="$(tr '\n' ' ' < "$scratch/list.txt")"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
g init -q
g add -A
base="$(g commit-tree "$(g write-tree)" -m base)"

reset_tree() {
  rm -rf "$repo/db" "$repo/scripts" "$repo/.github"
  cp -R "$scratch/orig/db" "$scratch/orig/scripts" "$scratch/orig/.github" "$repo/"
}

commit_case() {
  g add -A
  head="$(g commit-tree "$(g write-tree)" -p "$base" -m case)"
}

select_checks() {
  g diff --no-renames --name-only "$base...$head" \
    | LANG=en_US.UTF-8 ruby "$repo/scripts/schema_parity/pr_checks.rb" "$scratch/list.txt" "$@" 2>&1 | tr '\n' ' '
}

edit() {
  sed -i.bak "$2" "$repo/$1"
  rm -f "$repo/$1.bak"
}

bump_pin() {
  edit "$1" 's|actions/checkout@[0-9a-f]\{40\} # v7.0.1|actions/checkout@0123456789abcdef0123456789abcdef01234567 # v7.1.0|'
}

expect() {
  wanted="$1"
  label="$2"
  shift 2
  output="$(select_checks "$@")"
  [ "$output" = "$wanted" ]
  verdict $? "$label (selected: $output)"
}

reset_tree
bump_pin "$counterparts"
commit_case
expect "fresh " "a diff to ecto-counterparts.yml that changes only uses: lines selects only fresh" "$base...$head"

reset_tree
bump_pin "$counterparts"
bump_pin "$nightly"
commit_case
expect "fresh " "a pin bump in both workflow files selects only fresh" "$base...$head"

reset_tree
bump_pin "$counterparts"
edit "$counterparts" 's|timeout-minutes: 180|timeout-minutes: 170|'
commit_case
expect "$full" "a pin bump with any other edit to ecto-counterparts.yml selects every check" "$base...$head"

reset_tree
edit "$counterparts" 's|name: Checkout code|name: Check out the code|'
commit_case
expect "$full" "a step name edit to ecto-counterparts.yml selects every check" "$base...$head"

reset_tree
bump_pin "$counterparts"
echo 'echo helper' > "$repo/scripts/schema_parity/helper.sh"
commit_case
expect "$full" "a pin bump next to another shared input selects every check" "$base...$head"

reset_tree
bump_pin "$counterparts"
commit_case
expect "$full" "without a diff range a pin bump selects every check"
expect "$full" "an unresolvable diff range selects every check" "0000000000000000000000000000000000000000...$head"

reset_tree
rm "$repo/$counterparts"
commit_case
expect "$full" "deleting ecto-counterparts.yml selects every check" "$base...$head"

reset_tree
chmod +x "$repo/$counterparts"
commit_case
expect "$full" "a mode change without changed lines selects every check" "$base...$head"

reset_tree
edit "$nightly" 's|timeout-minutes: 180|timeout-minutes: 170|'
commit_case
expect "fresh " "an edit to ecto-nightly.yml alone still selects only fresh" "$base...$head"

echo "$failures failed"
[ "$failures" -eq 0 ]
