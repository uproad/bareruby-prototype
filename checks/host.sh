#!/usr/bin/env bash
# Run every sample checks/host.yml lists on the hosted entry twice — interpreted, with the
# machine's peripherals behind the calls, and executed natively — and compare what each
# printed. The native run is the oracle, so a pass means the two agree line for line.
#
#     ./checks/host.sh          # from anywhere; it stands itself in the repo root
#
# **What is named here is an entry, not a binding.** `--target=` takes an entry's name out
# of config/target.yml, so that is what this looks up and that is what it carries: this
# desk happens to call its hosted entry `host`, and another desk may not. Which entry it
# is comes from the binding, because that reaches one machine and one only.
#
# Nothing else is needed: no board, no emulator to install, no device on a bus. One line
# per sample, and a status the shell can read; what each run said is kept under
# .bareruby/checks/<sample>/ for reading a failure back.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

RUBY=${RUBY:-ruby}
RECORD=config/target.yml

NAME=$("$RUBY" -ryaml -e '
  entry = (YAML.safe_load_file(ARGV[0])["targets"] || []).find { |t| t["binding"] == "host" }
  puts entry ? entry["name"] : ""' "$RECORD")
[ -n "$NAME" ] || {
    echo "checks: $RECORD records no entry whose binding is host." >&2
    exit 2
}

WORK=.bareruby/checks
rm -rf "$WORK"

passed=0
failed=0
while IFS=$'\t' read -r sample seconds input; do
    name=$(basename "$sample" .rb)
    kept="$WORK/$name"
    mkdir -p "$kept"
    line=$(printf '%-34s' "$sample")

    # One invocation builds the entry and runs what it built, interpreted. Its own account
    # goes to a file and is pointed at only when something refused. What the interpreted
    # run is fed through --input is what the executed one reads on stdin — the same bytes
    # on both sides of the diff.
    if ! ./bareruby emulate --target="$NAME" --for="$seconds" \
         ${input:+--input="$input"} "$sample" \
         </dev/null >"$kept/emulate.log" 2>&1; then
        echo "$line  FAIL (the run refused; $kept/emulate.log)"
        failed=$((failed + 1))
        continue
    fi
    cp ".bareruby/emulate/$NAME/stdout.txt" "$kept/said.txt"
    cp ".bareruby/emulate/$NAME/uart.txt" "$kept/uart.txt"
    timeout 10 "./build/$NAME/bareruby_program" <"${input:-/dev/null}" \
        >"$kept/expected.txt" 2>/dev/null

    if diff "$kept/said.txt" "$kept/expected.txt" >"$kept/said.diff" 2>&1; then
        rm "$kept/said.diff"
        echo "$line  ok"
        passed=$((passed + 1))
    else
        echo "$line  FAIL ($kept/said.diff)"
        failed=$((failed + 1))
    fi
done < <("$RUBY" -ryaml -e '
  YAML.safe_load_file(ARGV[0])["checks"].each do |c|
    puts [c.fetch("sample"), c.fetch("for", 3), c.fetch("input", "")].join("\t")
  end' checks/host.yml)

echo "checks: $passed/$((passed + failed)) samples say interpreted what they say executed"
[ $failed -eq 0 ]
