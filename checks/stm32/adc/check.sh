#!/usr/bin/env bash
# Hold the STM32 ADC binding to fixed, reviewed answers under Renode.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
cd "$ROOT"

RUBY=${RUBY:-ruby}
TARGET=${1:-f446}
HERE=checks/stm32/adc
WORK=.bareruby/checks/stm32/adc
CONFIG_HOME=$PWD/.bareruby/renode-config
LOCK=gems/bareruby_prot-binding-stm32cube/lib/bareruby_prot/binding/stm32cube/data/sources.lock.yml
MODEL=$PWD/$HERE/model/BareRubyCheckAdc.cs
ATTACH='machine LoadPlatformDescriptionFromString "adc1: Analog.BareRubyCheckAdc @ sysbus 0x40012000"'

rm -rf "$WORK"
mkdir -p "$WORK" "$CONFIG_HOME"

RENODE=${RENODE:-$PWD/.tools/$($RUBY -ryaml -e '
  puts YAML.safe_load_file(ARGV[0]).dig("emulate", "renode", "directory")
' "$LOCK")/renode}

# The pinned Renode 1.16.1 models no F4 ADC, so the converter is this suite's own C#
# model, compiled at run time. The checks need its voltages set before the run and
# changed between slices of it, and register observations said before quit — none of
# which `bareruby emulate` runs. So the emulate verb builds with a stub standing in
# for Renode (it satisfies the verb by leaving an empty UART capture), and the one
# real Renode run below is ours, on the transformed script.
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
    # Semicolon rather than the gpio suite pipe, which steps needs for itself; a
    # whitespace separator would let read collapse the empty fields.
    puts [check.fetch("name"), check.fetch("observe", ""),
          check.fetch("give", ""), check.fetch("steps", "")].join(";")
  end
' "$HERE/checks.yml")

for check in "${checks[@]}"; do
    IFS=';' read -r name observe give steps <<<"$check"
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

    # The generated script, with the converter made real: its C# included and the
    # model attached right after the platform loads, the given voltages set before
    # the run, each step's changes applied between two slices of it, and any
    # observation said before quit.
    probe=""
    [ -n "$observe" ] && probe="$HERE/$observe"
    awk -v model="$MODEL" -v attach="$ATTACH" -v probe="$probe" \
        -v give="$give" -v steps="$steps" '
        function settings(pairs,    parts, pair, k, n) {
            n = split(pairs, parts, " ")
            for (k = 1; k <= n; k++) {
                split(parts[k], pair, "=")
                print "sysbus.adc1 SetChannelVoltage " pair[1] " " pair[2]
            }
        }
        BEGIN {
            if (probe != "") { while ((getline line < probe) > 0) { held = held line ORS } }
            step_count = split(steps, step_list, "|")
        }
        /^quit$/ { printf "%s", held }
        /^emulation RunFor / {
            for (i = 1; i <= step_count; i++) {
                print "emulation RunFor \"0:00:00.4\""
                settings(step_list[i])
            }
        }
        { print }
        /^machine LoadPlatformDescription @/ {
            print "include @" model
            print attach
            if (give != "") { settings(give) }
        }
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

echo "stm32 adc: $passed/$((passed + failed)) checks passed on $TARGET"
[ "$failed" -eq 0 ]
