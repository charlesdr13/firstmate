#!/usr/bin/env bash
# Drives the real bin/fm-captain-hold.sh against a disposable marked lab home.
set -u
WT=${WT:?}
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); "$WT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
trap 'rm -rf "$LAB"' EXIT
cat > "$LAB/.tasks.toml" <<'T'
backend = "markdown"

[markdown]
path = "data/backlog.md"
archive = "data/done-archive.md"
done_keep = 10
T
printf '## In flight\n\n## Queued\n\n## Done\n' > "$LAB/data/backlog.md"
H() { env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$LAB" "$WT/bin/fm-captain-hold.sh" "$@"; }
run() { echo; echo "\$ fm-captain-hold.sh $*"; H "$@" >"$LAB/o" 2>"$LAB/e"; rc=$?; sed 's/^/stdout: /' "$LAB/o"; sed 's/^/stderr: /' "$LAB/e"; echo "exit: $rc"; }
show() { echo "--- backlog row $1:"; (cd "$LAB" && tasks-axi show "$1" --full 2>&1 | sed 's/^/  /'); }
echo "## S1 new ask without --rec is refused, nothing written"
run hold q-norec --title "Pick a DB" --reason "Which DB?"
grep -c q-norec "$LAB/data/backlog.md" || echo "row q-norec absent: OK"
echo "## S2 new ask with options + rec renders numbered lines and Rec:"
run hold q-db --title "Pick a DB" --reason "Which DB?" --option Postgres --option SQLite --rec 1 --key pick-db
show q-db
echo "## S3 fifth --option refused"
run hold q-five --title "x" --reason "r" --option a --option b --option c --option d --option e --rec 1
grep -c q-five "$LAB/data/backlog.md" || echo "row q-five absent: OK"
echo "## S4 --option without --rec refused (review decision)"
run hold q-optnorec --title "x" --reason "r" --option a --option b
echo "## S5 duplicate key attaches to existing hold"
run hold q-db-dup --title "Pick a DB again" --reason "DB?" --rec Postgres --key pick-db
grep -c q-db-dup "$LAB/data/backlog.md" || echo "row q-db-dup absent: OK"
echo "## S6 distinct key stays distinct"
run hold q-cache --title "Pick a cache" --reason "Cache?" --rec Redis --key pick-cache
echo "## S7 invalid key rejected"
run hold q-bad --title "x" --reason "r" --rec 1 --key 'Bad Key!'
echo "## S8 retry on already-captain-held task needs no --rec"
run hold q-db --reason "Which DB? (retry)"
echo "## S9 --until deferral needs no --rec"
run hold q-cache --reason "revisit" --until 2099-01-01
echo "## S10 stale key cleared on re-hold after release (review decision)"
printf 'Use Postgres.\n' > "$LAB/ans"
run answer q-db --decision-file "$LAB/ans" --release
run hold q-db --reason "New unrelated ask" --rec yes
show q-db
run hold q-new --title "Another DB ask" --reason "r" --rec 1 --key pick-db
echo "## S11 read paths unaffected"
run open q-db
run open q-new
