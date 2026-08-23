#!/usr/bin/env bash
# Hold the STM32 I2C binding to fixed, reviewed answers against the check sensor.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
cd "$ROOT"

RUBY=${RUBY:-ruby}
TARGET=${1:-f446}
HERE=checks/stm32/i2c
WORK=.bareruby/checks/stm32/i2c
CONFIG_HOME=$PWD/.bareruby/renode-config
LOCK=gems/bareruby_prot-binding-stm32cube/lib/bareruby_prot/binding/stm32cube/data/sources.lock.yml
SENSOR=$PWD/$HERE/sensor/BareRubyCheckSensor.cs
ATTACH='machine LoadPlatformDescriptionFromString "sensor: I2C.BareRubyCheckSensor @ i2c1 0x76"'

rm -rf "$WORK"
mkdir -p "$WORK" "$CONFIG_HOME"

RENODE=${RENODE:-$PWD/.tools/$($RUBY -ryaml -e '
  puts YAML.safe_load_file(ARGV[0]).dig("emulate", "renode", "directory")
' "$LOCK")/renode}

# Every check needs the sensor on the bus, and `bareruby emulate` runs Renode with the
# plain machine — where an I2C program hangs against nobody. So the emulate verb builds
# with a stub standing in for Renode (it satisfies the verb by leaving an empty UART
# capture), and the one real Renode run below is ours, on the transformed script.
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
          check.fetch("capture", "")].join("|")
  end
' "$HERE/checks.yml")

for check in "${checks[@]}"; do
    IFS='|' read -r name observe capture <<<"$check"
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

    # The generated script, with the sensor made real: its C# included before the
    # machine exists, the device attached right after the platform loads, and any
    # register probe said before quit.
    probe=""
    [ -n "$observe" ] && probe="$HERE/$observe"
    awk -v sensor="$SENSOR" -v attach="$ATTACH" -v probe="$probe" '
        BEGIN {
            print "include @" sensor
            if (probe != "") { while ((getline line < probe) > 0) { held = held line ORS } }
        }
        /^quit$/ { printf "%s", held }
        { print }
        /^machine LoadPlatformDescription @/ { print attach }
    ' ".bareruby/emulate/$TARGET/run.resc" >"$kept/run.resc"

    rm -f ".bareruby/emulate/$TARGET/uart.log"
    XDG_CONFIG_HOME="$CONFIG_HOME" "$RENODE" --disable-xwt --console --plain \
        -e "include @$PWD/$kept/run.resc" >"$kept/renode.log" 2>&1

    if [ "$capture" = hex ]; then
        "$RUBY" -e '
          bytes = File.binread(ARGV.fetch(0)).bytes
          File.write(ARGV.fetch(1), bytes.map { |byte| format("%02X", byte) }.join(" ") + "\n")
        ' ".bareruby/emulate/$TARGET/uart.log" "$kept/uart.txt"
    else
        "$RUBY" -e '
          File.write(ARGV.fetch(1), File.binread(ARGV.fetch(0)).gsub("\r\n", "\n"))
        ' ".bareruby/emulate/$TARGET/uart.log" "$kept/uart.txt"
    fi
    ok=1
    if ! diff -u "$expected" "$kept/uart.txt" >"$kept/uart.diff" 2>&1; then
        ok=0
    else
        rm "$kept/uart.diff"
    fi

    if [ -n "$observe" ]; then
        tr -d '\r' <"$kept/renode.log" | grep -E '^0x[0-9A-Fa-f]{8}$' \
            >"$kept/registers.txt"
        if ! diff -u "$HERE/expected/$name.registers" "$kept/registers.txt" \
             >"$kept/registers.diff" 2>&1; then
            ok=0
        else
            rm "$kept/registers.diff"
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

echo "stm32 i2c: $passed/$((passed + failed)) checks passed on $TARGET"
[ "$failed" -eq 0 ]
