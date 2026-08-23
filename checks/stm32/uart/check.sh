#!/usr/bin/env bash
# Hold the STM32 UART binding to fixed, reviewed output and peripheral-register answers.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
cd "$ROOT"

RUBY=${RUBY:-ruby}
TARGET=${1:-f446}
HERE=checks/stm32/uart
WORK=.bareruby/checks/stm32/uart
CONFIG_HOME=$PWD/.bareruby/renode-config
LOCK=gems/bareruby_prot-binding-stm32cube/lib/bareruby_prot/binding/stm32cube/data/sources.lock.yml

rm -rf "$WORK"
mkdir -p "$WORK" "$CONFIG_HOME"

RENODE=${RENODE:-$PWD/.tools/$($RUBY -ryaml -e '
  puts YAML.safe_load_file(ARGV[0]).dig("emulate", "renode", "directory")
' "$LOCK")/renode}

passed=0
failed=0
while IFS='|' read -r name input observe; do
    sample="$HERE/samples/$name.rb"
    expected="$HERE/expected/$name.txt"
    kept="$WORK/$name"
    mkdir -p "$kept"
    arguments=()
    [ -n "$input" ] && arguments+=("--input=$HERE/$input")

    if ! XDG_CONFIG_HOME="$CONFIG_HOME" ./bareruby emulate "$sample" \
         "--target=$TARGET" --for=1 "${arguments[@]}" \
         </dev/null >"$kept/emulate.log" 2>&1; then
        printf '%-22s FAIL (emulate refused; %s)\n' "$name" "$kept/emulate.log"
        failed=$((failed + 1))
        continue
    fi

    cp ".bareruby/emulate/$TARGET/uart.txt" "$kept/uart.txt"
    ok=1
    if ! diff -u "$expected" "$kept/uart.txt" >"$kept/uart.diff" 2>&1; then
        ok=0
    else
        rm "$kept/uart.diff"
    fi

    if [ -n "$observe" ]; then
        awk 'FNR == NR { probe = probe $0 ORS; next }
             /^quit$/ { printf "%s", probe }
             { print }' "$HERE/$observe" ".bareruby/emulate/$TARGET/run.resc" \
             >"$kept/observe.resc"
        XDG_CONFIG_HOME="$CONFIG_HOME" "$RENODE" --disable-xwt --console --plain \
            -e "include @$PWD/$kept/observe.resc" >"$kept/observe.log" 2>&1
        tr -d '\r' <"$kept/observe.log" | grep -E '^0x[0-9A-Fa-f]{8}$' \
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
done < <("$RUBY" -ryaml -e '
  YAML.safe_load_file(ARGV[0])["checks"].each do |check|
    puts [check.fetch("name"), check.fetch("input", ""),
          check.fetch("observe", "")].join("|")
  end
' "$HERE/checks.yml")

echo "stm32 uart: $passed/$((passed + failed)) checks passed on $TARGET"
[ "$failed" -eq 0 ]
