#!/usr/bin/env bash
# Hold the STM32 sleep and timing binding to fixed, reviewed answers under Renode.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
cd "$ROOT"

RUBY=${RUBY:-ruby}
TARGET=${1:-f446}
HERE=checks/stm32/sleep
WORK=.bareruby/checks/stm32/sleep
CONFIG_HOME=$PWD/.bareruby/renode-config
LOCK=gems/bareruby_prot-binding-stm32cube/lib/bareruby_prot/binding/stm32cube/data/sources.lock.yml
DUTY_MARK=BARERUBY_DUTY_OK

rm -rf "$WORK"
mkdir -p "$WORK" "$CONFIG_HOME"

RENODE=${RENODE:-$PWD/.tools/$($RUBY -ryaml -e '
  puts YAML.safe_load_file(ARGV[0]).dig("emulate", "renode", "directory")
' "$LOCK")/renode}

# Some checks need a byte injected mid-wait, and the duty checks need Renode's LED
# tester asserting over the run — `bareruby emulate` does neither. So the emulate verb
# builds with a stub standing in for Renode (it satisfies the verb by leaving an empty
# UART capture), and the one real Renode run below is ours, on the transformed script.
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
    puts [check.fetch("name"), check.fetch("feed", ""),
          check.fetch("duty", ""), check.fetch("for", 1)].join("|")
  end
' "$HERE/checks.yml")

for check in "${checks[@]}"; do
    IFS='|' read -r name feed duty for_seconds <<<"$check"
    sample="$HERE/samples/$name.rb"
    expected="$HERE/expected/$name.txt"
    kept="$WORK/$name"
    mkdir -p "$kept"

    if ! RENODE="$STUB" XDG_CONFIG_HOME="$CONFIG_HOME" ./bareruby emulate "$sample" \
         "--target=$TARGET" "--for=$for_seconds" \
         </dev/null >"$kept/emulate.log" 2>&1; then
        printf '%-24s FAIL (build refused; %s)\n' "$name" "$kept/emulate.log"
        failed=$((failed + 1))
        continue
    fi

    # The generated script, transformed. A feed is injected between two slices of the
    # run, so the byte lands mid-wait. A duty check trades the timed run for the LED
    # tester: a failed assertion aborts the script, so the marker after it is only
    # ever said on success.
    feed_path=""
    [ -n "$feed" ] && feed_path="$HERE/$feed"
    awk -v feed="$feed_path" -v duty="$duty" -v mark="$DUTY_MARK" '
        BEGIN {
            if (feed != "") { while ((getline line < feed) > 0) { held = held line ORS } }
        }
        /^emulation RunFor / {
            if (duty != "") {
                print "emulation CreateLEDTester \"lt\" sysbus.gpioPortA.led"
                print "start"
                print "lt AssertDutyCycle " duty
                print "lt InfoLog \"" mark "\""
                next
            }
            if (feed != "") {
                print "emulation RunFor \"0:00:00.2\""
                printf "%s", held
            }
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
    fi
    [ -s "$kept/uart.diff" ] || rm -f "$kept/uart.diff"

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

echo "stm32 sleep: $passed/$((passed + failed)) checks passed on $TARGET"
[ "$failed" -eq 0 ]
