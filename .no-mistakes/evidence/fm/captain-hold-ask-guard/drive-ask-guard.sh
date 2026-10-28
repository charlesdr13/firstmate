#!/usr/bin/env bash
# Live drive of bin/fm-captain-hold.sh hold's opt-in ask guard against
# disposable lab homes (bin/fm-lab-home.sh) and the real tasks-axi.
# Usage: drive-ask-guard.sh <worktree>
set -u
WT=$1
CAP="$WT/bin/fm-captain-hold.sh"
LABS=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
trap 'rm -rf "$LABS"' EXIT
PRIMARY=$("$WT/bin/fm-lab-home.sh" create "$LABS/primary")
MATE=$("$WT/bin/fm-lab-home.sh" create "$LABS/mate")
WORKLOG="$LABS/worklog"; mkdir -p "$WORKLOG/data"
for h in "$PRIMARY" "$MATE" "$WORKLOG"; do
  printf 'backend = "markdown"\n\n[markdown]\npath = "data/backlog.md"\narchive = "data/done-archive.md"\ndone_keep = 10\n' > "$h/.tasks.toml"
  printf '## In flight\n\n## Queued\n\n## Done\n' > "$h/data/backlog.md"
done

step() { printf '\n=== %s\n' "$*"; }
hold() {  # <home> <args...>: run the real script as an end user would
  local home=$1; shift
  printf '$ FM_HOME=%s fm-captain-hold.sh hold %s\n' "${home#"$LABS"/}" "$(printf '%q ' "$@")"
  ( cd "$home" && env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE \
      -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$home" "$CAP" hold "$@" ) 2>&1
  local rc=$?; printf '[exit %s]\n' "$rc"; return "$rc"
}
tx() { local home=$1; shift; ( cd "$home" && tasks-axi "$@" ) 2>&1; }
exists() { tx "$1" show "$2" >/dev/null 2>&1 && echo "task $2: EXISTS" || echo "task $2: absent"; }

step "1. guard off by default: a reason with no Rec is accepted"
hold "$PRIMARY" p-off --title "Guard off" --reason "what now?"

step "2. fleet: register mate as a local secondmate of primary; configure the guard on primary only"
printf 'schema=fm-secondmate-parent.v1\nroute=local\nparent_home=%s\n' "$PRIMARY" > "$MATE/.fm-secondmate-parent"
printf -- '- tesla - Platform (home: %s; scope: platform; projects: sample; added 2026-10-28)\n' "$MATE" > "$PRIMARY/data/secondmates.md"
printf '# lab guard\nrequire-rec\ndedupe\nfleet-data %s/data  # work log\n' "$WORKLOG" > "$PRIMARY/config/captain-hold-guard"
cat "$PRIMARY/config/captain-hold-guard"

step "3. inheritance: the primary's config/captain-hold-guard propagates to the secondmate home"
( . "$WT/bin/fm-config-inherit-lib.sh"; propagate_inheritable_config "$PRIMARY/config" "$MATE/config" "$PRIMARY" ) 2>&1 | grep -i 'captain-hold-guard' || true
cmp "$PRIMARY/config/captain-hold-guard" "$MATE/config/captain-hold-guard" && echo "mate config/captain-hold-guard == primary's"

step "4. require-rec: an ask with no Rec is refused and creates no task"
hold "$PRIMARY" p-norec --title "No rec" --reason "what do you want to do here?"
exists "$PRIMARY" p-norec
step "4b. Recommend: form is accepted"
hold "$PRIMARY" p-rec --title "Rotate" --reason "Rotate the key? Recommend: yes, because it leaked"

step "5. dedupe across the fleet: mate files a hold on a PR, primary then asks about the same PR"
hold "$MATE" m-pr --title "Merge widgets 26" --reason "Merge https://github.com/Acme/widgets/pull/26? Rec: yes, because green"
hold "$PRIMARY" p-dup --title "Dup" --reason "Merge https://github.com/acme/WIDGETS/issues/26 now? Rec: yes, because green"
exists "$PRIMARY" p-dup
step "5b. the same PR via the fleet-data work log (hold filed there with tasks-axi directly)"
tx "$WORKLOG" add w-pr "Dashboard 203" --repo sample >/dev/null
tx "$WORKLOG" hold w-pr --kind captain --reason "ship https://github.com/acme/dashboard/pull/203 Rec: yes" >/dev/null
hold "$MATE" m-dup --title "Dup" --reason "Ship https://github.com/Acme/dashboard/pull/203? Rec: yes, because green"
step "5c. re-holding the hold that already cites the PR is allowed"
hold "$MATE" m-pr --reason "Still merge https://github.com/Acme/widgets/pull/26? Rec: yes, because green"
step "5d. a bare owner/repo#n is not a URL, so it is not matched (documented)"
hold "$PRIMARY" p-bare --title "Bare" --reason "Merge acme/widgets#26? Rec: yes, because green"

step "6. cap: live = no --until or lapsed --until; a future --until snooze does not count"
tx "$PRIMARY" add p-snooze "Snoozed" --repo sample >/dev/null
tx "$PRIMARY" hold p-snooze --kind captain --until 2099-01-01 --reason "later Rec: wait" >/dev/null
tx "$PRIMARY" add p-lapsed "Lapsed" --repo sample >/dev/null
tx "$PRIMARY" hold p-lapsed --kind captain --until 2020-01-01 --reason "merge https://github.com/acme/api/pull/9 Rec: yes" >/dev/null
echo "tasks-axi --state held in primary (lapsed one is omitted by tasks-axi itself):"
tx "$PRIMARY" list --state held --fields hold_kind,hold_until,held
echo "live fleet captain holds: p-off p-rec p-bare p-lapsed (primary), m-pr (mate), w-pr (worklog) = 6; p-snooze snoozed"
printf 'cap 6\n' >> "$PRIMARY/config/captain-hold-guard"; cp "$PRIMARY/config/captain-hold-guard" "$MATE/config/captain-hold-guard"
hold "$PRIMARY" p-cap --title "Cap" --reason "Pay the invoice? Rec: yes, because due"
exists "$PRIMARY" p-cap
step "6b. raise cap to 7: snoozed hold is not counted, so a 7th live hold goes through"
sed -i 's/^cap 6$/cap 7/' "$PRIMARY/config/captain-hold-guard"
hold "$PRIMARY" p-cap --title "Cap" --reason "Pay the invoice? Rec: yes, because due"
sed -i 's/^cap 7$/cap 6/' "$PRIMARY/config/captain-hold-guard"
step "6c. dedupe sees the lapsed hold (tasks-axi --state held omits it)"
hold "$PRIMARY" p-lapdup --title "Lapsed dup" --over-cap urgent --reason "Merge https://github.com/acme/api/pull/9? Rec: yes, because green"
step "6d. re-holding an open hold at the cap is allowed (lapsed one and active one)"
hold "$PRIMARY" p-lapsed --reason "merge https://github.com/acme/api/pull/9 today? Rec: yes"
hold "$PRIMARY" p-rec --reason "Rotate the key today? Rec: yes, because it leaked"

step "7. adversarial: --over-cap text cannot stand in for the ask's Rec or trip dedupe"
hold "$PRIMARY" p-urgent --title "Urgent" --reason "Pay the invoice?" --over-cap "rec: https://github.com/acme/widgets/pull/26"
exists "$PRIMARY" p-urgent
step "7b. --over-cap lets an urgent ask past the cap and is recorded as an Over cap: line"
hold "$PRIMARY" p-urgent --title "Urgent" --reason "Pay vendor today? Rec: yes, because service cuts off" \
  --over-cap "vendor cuts service tonight, see https://github.com/acme/widgets/pull/26"
grep -n 'p-urgent' -A3 "$PRIMARY/data/backlog.md"
. "$WT/bin/fm-hold-reason-lib.sh"; tx "$PRIMARY" show p-urgent --full | fm_hold_reason_decode_stream toon | grep 'Over cap:'
step "7c. empty --over-cap is refused"
hold "$PRIMARY" p-x --title "X" --reason "Ok? Rec: yes" --over-cap ""

step "8. the secondmate, under its inherited guard, is refused at the fleet cap too"
hold "$MATE" m-cap --title "Mate cap" --reason "Bump the dep? Rec: yes, because CVE"

step "9. adversarial: an unreadable fleet backlog is warned about and skipped, not blocking"
BROKEN="$LABS/broken"; mkdir -p "$BROKEN/data"; printf 'backend = "nonsense"\n' > "$BROKEN/.tasks.toml"; printf 'garbage\n' > "$BROKEN/data/backlog.md"
printf 'fleet-data %s/data\n' "$BROKEN" >> "$PRIMARY/config/captain-hold-guard"
hold "$PRIMARY" p-more --title "More" --over-cap "urgent" --reason "Ship it? Rec: yes, because green"

step "10. malformed config refuses every hold and names the line"
printf 'cap 3\n' >> "$PRIMARY/config/captain-hold-guard"
hold "$PRIMARY" p-bad --title "Bad" --reason "Ok? Rec: yes"
printf 'require-rec\ncap 0\n' > "$PRIMARY/config/captain-hold-guard"
hold "$PRIMARY" p-bad --title "Bad" --reason "Ok? Rec: yes"
printf 'requre-rec\n' > "$PRIMARY/config/captain-hold-guard"
hold "$PRIMARY" p-bad --title "Bad" --reason "Ok? Rec: yes"
exists "$PRIMARY" p-bad

step "final primary backlog"
cat "$PRIMARY/data/backlog.md"
