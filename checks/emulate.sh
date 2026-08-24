#!/usr/bin/env bash
# Run every sample checks/emulate.yml lists through `bareruby emulate` and compare the
# UART against the same program run on the host — the host build is the oracle, so a
# pass means the firmware and the host agree line for line.
#
#     ./checks/emulate.sh          # from anywhere; it stands itself in the repo root
#
# The targets are read from config/target.yml, exactly as every verb reads them: the
# hosted entry is the oracle, and every stm32cube entry is emulated. **What is looked up
# is an entry's name**, because that is what `--target=` takes — this desk happens to call
# its hosted entry `host`, and another desk may not. A desk and CI
# run the same script against their own record. One line per sample, a verdict per
# board, and a status the shell can read; what each run said is kept under
# .bareruby/checks/<sample>/ for reading a failure back.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

RUBY=${RUBY:-ruby}
RECORD=config/target.yml

ORACLE=$("$RUBY" -ryaml -e '
  entry = (YAML.safe_load_file(ARGV[0])["targets"] || []).find { |t| t["binding"] == "host" }
  puts entry ? entry["name"] : ""' "$RECORD")
[ -n "$ORACLE" ] || {
    echo "checks: $RECORD records no entry whose binding is host, and that build is the oracle." >&2
    exit 2
}
mapfile -t BOARDS < <("$RUBY" -ryaml -e '
  (YAML.safe_load_file(ARGV[0])["targets"] || []).each do |t|
    puts t["name"] if t["binding"] == "stm32cube"
  end' "$RECORD")
[ ${#BOARDS[@]} -gt 0 ] || {
    echo "checks: $RECORD records no stm32cube entry — nothing to emulate." >&2
    exit 2
}

WORK=.bareruby/checks
rm -rf "$WORK"

TARGETS=()
for board in "${BOARDS[@]}"; do TARGETS+=("--target=$board"); done

passed=0
failed=0
while IFS=$'\t' read -r sample seconds input; do
    name=$(basename "$sample" .rb)
    kept="$WORK/$name"
    mkdir -p "$kept"
    line=$(printf '%-34s' "$sample")

    # **The oracle is built rather than emulated.** Its machine has an emulator of its own
    # now — the peripherals it carries are objects, and `emulate` reaches them — but what
    # this check wants from it is the executed run, so it is only built. Its own account
    # goes to a file and is pointed at only when something refused. What the boards are fed
    # through --input is what the oracle reads on stdin — the same bytes on both sides of
    # the diff.
    if ! ./bareruby build --target="$ORACLE" "$sample" \
         </dev/null >"$kept/emulate.log" 2>&1; then
        echo "$line  FAIL (the oracle refused to build; $kept/emulate.log)"
        failed=$((failed + 1))
        continue
    fi
    if ! ./bareruby emulate "${TARGETS[@]}" --for="$seconds" \
         ${input:+--input="$input"} "$sample" \
         </dev/null >>"$kept/emulate.log" 2>&1; then
        echo "$line  FAIL (emulate refused; $kept/emulate.log)"
        failed=$((failed + 1))
        continue
    fi
    timeout 10 "./build/$ORACLE/bareruby_program" <"${input:-/dev/null}" \
        >"$kept/expected.txt" 2>/dev/null

    ok=1
    for board in "${BOARDS[@]}"; do
        cp ".bareruby/emulate/$board/uart.txt" "$kept/$board.txt"
        if diff "$kept/$board.txt" "$kept/expected.txt" \
             >"$kept/$board.diff" 2>&1; then
            rm "$kept/$board.diff"
            line+="  $board ok"
        else
            line+="  $board FAIL"
            ok=0
        fi
    done
    echo "$line"
    if [ $ok -eq 1 ]; then passed=$((passed + 1)); else failed=$((failed + 1)); fi
done < <("$RUBY" -ryaml -e '
  YAML.safe_load_file(ARGV[0])["checks"].each do |c|
    puts [c.fetch("sample"), c.fetch("for", 3), c.fetch("input", "")].join("\t")
  end' checks/emulate.yml)

echo "checks: $passed/$((passed + failed)) samples agree with the host," \
     "on ${#BOARDS[@]} board$([ ${#BOARDS[@]} -ne 1 ] && echo s) each"
[ $failed -eq 0 ]
