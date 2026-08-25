#!/usr/bin/env bash
# Hold the STM32 onboard LED binding to fixed, reviewed answers under Renode.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
cd "$ROOT"

RUBY=${RUBY:-ruby}
TARGET=${1:-f446}
HERE=checks/stm32/onboard_led
WORK=.bareruby/checks/stm32/onboard_led
CONFIG_HOME=$PWD/.bareruby/renode-config
LOCK=gems/bareruby_prot-binding-stm32cube/lib/bareruby_prot/binding/stm32cube/data/sources.lock.yml

rm -rf "$WORK"
mkdir -p "$WORK" "$CONFIG_HOME"

RENODE=${RENODE:-$PWD/.tools/$($RUBY -ryaml -e '
  puts YAML.safe_load_file(ARGV[0]).dig("emulate", "renode", "directory")
' "$LOCK")/renode}

# The LED-state and register observations have to be said to Renode — mid-run for the
# cycling check, before quit for the rest — and `bareruby emulate` runs Renode with
# neither. So the emulate verb builds with a stub standing in for Renode (it satisfies
# the verb by leaving an empty UART capture), and the one real Renode run below is
# ours, on the transformed script.
STUB=$WORK/renode-stub
cat >"$STUB" <<STUB
#!/bin/sh
touch "$PWD/.bareruby/emulate/$TARGET/uart.log"
exit 0
STUB
chmod +x "$STUB"

passed=0
failed=0
mapfile -t checks < <("$RUBY" -ryaml -e '
  YAML.safe_load_file(ARGV[0])["checks"].each do |check|
    puts [check.fetch("name"), check.fetch("observe", ""),
          check.fetch("during", "")].join("|")
  end
' "$HERE/checks.yml")

for check in "${checks[@]}"; do
    IFS='|' read -r name observe during <<<"$check"
    sample="$HERE/samples/$name.rb"
    expected="$HERE/expected/$name.txt"
    kept="$WORK/$name"
    mkdir -p "$kept"

    if ! RENODE="$STUB" XDG_CONFIG_HOME="$CONFIG_HOME" ./bareruby emulate "$sample" \
         "--target=$TARGET" --for=1 \
         </dev/null >"$kept/emulate.log" 2>&1; then
        printf '%-22s FAIL (build refused; %s)\n' "$name" "$kept/emulate.log"
        failed=$((failed + 1))
        continue
    fi

    # The generated script, transformed: a mid-run observation slipped between two
    # slices of the run when the check asks for one, and the final observation said
    # before quit.
    probe=""
    [ -n "$observe" ] && probe="$HERE/$observe"
    mid=""
    [ -n "$during" ] && mid="$HERE/$during"
    awk -v probe="$probe" -v mid="$mid" '
        BEGIN {
            if (probe != "") { while ((getline line < probe) > 0) { held = held line ORS } }
            if (mid != "") { while ((getline line < mid) > 0) { midheld = midheld line ORS } }
        }
        /^quit$/ { printf "%s", held }
        mid != "" && /^emulation RunFor / {
            print "emulation RunFor \"0:00:00.2\""
            printf "%s", midheld
        }
        { print }
    ' ".bareruby/emulate/$TARGET/run.resc" >"$kept/run.resc"

    rm -f ".bareruby/emulate/$TARGET/uart.log"
    XDG_CONFIG_HOME="$CONFIG_HOME" "$RENODE" --disable-xwt --console --plain \
        -e "include @$PWD/$kept/run.resc" >"$kept/renode.log" 2>&1

    "$RUBY" -e '
      File.write(ARGV.fetch(1), File.binread(ARGV.fetch(0)).gsub("\r\n", "\n"))
    ' ".bareruby/emulate/$TARGET/uart.log" "$kept/uart.txt"
    ok=1
    if ! diff -u "$expected" "$kept/uart.txt" >"$kept/uart.diff" 2>&1; then
        ok=0
    else
        rm "$kept/uart.diff"
    fi

    if [ -n "$observe" ]; then
        tr -d '\r' <"$kept/renode.log" | grep -E '^(0x[0-9A-Fa-f]{8}|True|False)$' \
            >"$kept/observed.txt"
        if ! diff -u "$HERE/expected/$name.registers" "$kept/observed.txt" \
             >"$kept/observed.diff" 2>&1; then
            ok=0
        else
            rm "$kept/observed.diff"
        fi
    fi

    if [ "$ok" -eq 1 ]; then
        printf '%-22s ok\n' "$name"
        passed=$((passed + 1))
    else
        printf '%-22s FAIL (%s)\n' "$name" "$kept"
        failed=$((failed + 1))
    fi
done

echo "stm32 onboard_led: $passed/$((passed + failed)) checks passed on $TARGET"
[ "$failed" -eq 0 ]
