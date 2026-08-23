#!/usr/bin/env bash
# Run every sample checks/simulate.yml lists under the simulator and compare what it
# printed against the same program run natively on this desk — the native build is the
# oracle, so a pass means the interpreted run and the real one agree line for line.
#
#     ./checks/simulate.sh          # from anywhere; it stands itself in the repo root
#
# The host entry is read from config/target.yml, exactly as every verb reads it. Nothing
# else is needed: no board, no emulator to install, no device on a bus. One line per
# sample, and a status the shell can read; what each run said is kept under
# .bareruby/checks/<sample>/ for reading a failure back.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

RUBY=${RUBY:-ruby}
RECORD=config/target.yml

HOST=$("$RUBY" -ryaml -e '
  entry = (YAML.safe_load_file(ARGV[0])["targets"] || []).find { |t| t["binding"] == "host" }
  puts entry ? entry["name"] : ""' "$RECORD")
[ -n "$HOST" ] || {
    echo "checks: $RECORD records no host entry, and the host build is the oracle." >&2
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

    # One invocation builds the host entry and runs what it built under the simulator.
    # Its own account goes to a file and is pointed at only when something refused. What
    # the simulated run is fed through --input is what the native one reads on stdin —
    # the same bytes on both sides of the diff.
    if ! ./bareruby emulate --target="$HOST" --for="$seconds" \
         ${input:+--input="$input"} "$sample" \
         </dev/null >"$kept/simulate.log" 2>&1; then
        echo "$line  FAIL (the run refused; $kept/simulate.log)"
        failed=$((failed + 1))
        continue
    fi
    cp ".bareruby/emulate/$HOST/stdout.txt" "$kept/said.txt"
    cp ".bareruby/emulate/$HOST/uart.txt" "$kept/uart.txt"
    timeout 10 "./build/$HOST/bareruby_program" <"${input:-/dev/null}" \
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
  end' checks/simulate.yml)

echo "checks: $passed/$((passed + failed)) samples say on the simulator what they say here"
[ $failed -eq 0 ]
