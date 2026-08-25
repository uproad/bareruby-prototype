#!/usr/bin/env bash
# Hold the STM32 PWM binding to fixed, reviewed answers under Renode.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
cd "$ROOT"

RUBY=${RUBY:-ruby}
TARGET=${1:-f446}
HERE=checks/stm32/pwm
WORK=.bareruby/checks/stm32/pwm
CONFIG_HOME=$PWD/.bareruby/renode-config
LOCK=gems/bareruby_prot-binding-stm32cube/lib/bareruby_prot/binding/stm32cube/data/sources.lock.yml
DUTY_MARK=BARERUBY_DUTY_OK

rm -rf "$WORK"
mkdir -p "$WORK" "$CONFIG_HOME"

RENODE=${RENODE:-$PWD/.tools/$($RUBY -ryaml -e '
  puts YAML.safe_load_file(ARGV[0]).dig("emulate", "renode", "directory")
' "$LOCK")/renode}

# The register observations have to be said before quit and the duty check needs
# Renode's LED tester asserting over the run — `bareruby emulate` does neither. So the
# emulate verb builds with a stub standing in for Renode (it satisfies the verb by
# leaving an empty UART capture), and the one real Renode run below is ours, on the
# transformed script.
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
          check.fetch("duty", "")].join("|")
  end
' "$HERE/checks.yml")

for check in "${checks[@]}"; do
    IFS='|' read -r name observe duty <<<"$check"
    sample="$HERE/samples/$name.rb"
    expected="$HERE/expected/$name.txt"
    kept="$WORK/$name"
    mkdir -p "$kept"

    if ! RENODE="$STUB" XDG_CONFIG_HOME="$CONFIG_HOME" ./bareruby emulate "$sample" \
         "--target=$TARGET" --for=1 \
         </dev/null >"$kept/emulate.log" 2>&1; then
        printf '%-24s FAIL (build refused; %s)\n' "$name" "$kept/emulate.log"
        failed=$((failed + 1))
        continue
    fi

    # The generated script, transformed: observations said before quit, and the duty
    # check trading the timed run for the LED tester — a failed assertion aborts the
    # script, so the marker after it is only ever said on success.
    probe=""
    [ -n "$observe" ] && probe="$HERE/$observe"
    awk -v probe="$probe" -v duty="$duty" -v mark="$DUTY_MARK" '
        BEGIN {
            if (probe != "") { while ((getline line < probe) > 0) { held = held line ORS } }
        }
        /^quit$/ { printf "%s", held }
        duty != "" && /^emulation RunFor / {
            print "emulation CreateLEDTester \"lt\" sysbus.gpioPortA.led"
            print "start"
            print "lt AssertDutyCycle " duty
            print "lt InfoLog \"" mark "\""
            next
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
        tr -d '\r' <"$kept/renode.log" | grep -E '^0x[0-9A-Fa-f]{8}$' \
            >"$kept/observed.txt"
        if ! diff -u "$HERE/expected/$name.registers" "$kept/observed.txt" \
             >"$kept/observed.diff" 2>&1; then
            ok=0
        else
            rm "$kept/observed.diff"
        fi
    fi

    if [ -n "$duty" ]; then
        grep -o "$DUTY_MARK" "$kept/renode.log" | head -1 >"$kept/duty.txt"
        if ! diff -u "$HERE/expected/$name.duty" "$kept/duty.txt" \
             >"$kept/duty.diff" 2>&1; then
            ok=0
        else
            rm "$kept/duty.diff"
        fi
    fi

    if [ "$ok" -eq 1 ]; then
        printf '%-24s ok\n' "$name"
        passed=$((passed + 1))
    else
        printf '%-24s FAIL (%s)\n' "$name" "$kept"
        failed=$((failed + 1))
    fi
done

echo "stm32 pwm: $passed/$((passed + failed)) checks passed on $TARGET"
[ "$failed" -eq 0 ]
