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
mapfile -t checks < <("$RUBY" -ryaml -e '
  YAML.safe_load_file(ARGV[0])["checks"].each do |check|
    puts [check.fetch("name"), check.fetch("input", ""),
          check.fetch("observe", ""), check.fetch("input_bytes", ""),
          check.fetch("feed", ""), check.fetch("chunk_size", ""),
          check.fetch("capture", "")].join("|")
  end
' "$HERE/checks.yml")

for check in "${checks[@]}"; do
    IFS='|' read -r name input observe input_bytes feed chunk_size capture <<<"$check"
    sample="$HERE/samples/$name.rb"
    expected="$HERE/expected/$name.txt"
    kept="$WORK/$name"
    mkdir -p "$kept"
    arguments=()
    feed_path=""
    if [ -n "$input_bytes" ]; then
        input="$kept/input.bin"
        "$RUBY" -e '
          count = Integer(ARGV.fetch(0))
          File.binwrite(ARGV.fetch(1), (0...count).map { |i| i % 251 + 1 }.pack("C*"))
        ' "$input_bytes" "$input"
    fi
    if [ -n "$chunk_size" ]; then
        feed_path="$kept/input.resc"
        "$RUBY" -e '
          bytes = File.binread(ARGV.fetch(0)).bytes
          chunk = Integer(ARGV.fetch(1))
          File.open(ARGV.fetch(2), "w") do |file|
            file.puts %(emulation RunFor "0:00:00.005")
            bytes.each_slice(chunk) do |part|
              part.each { |byte| file.puts format("sysbus.usart2 WriteChar 0x%02X", byte) }
              file.puts %(emulation RunFor "0:00:00.050")
            end
          end
        ' "$input" "$chunk_size" "$feed_path"
        input=""
    elif [ -n "$input_bytes" ]; then
        arguments+=("--input=$input")
    elif [ -n "$input" ]; then
        arguments+=("--input=$HERE/$input")
    fi
    [ -n "$feed" ] && feed_path="$HERE/$feed"

    if ! XDG_CONFIG_HOME="$CONFIG_HOME" ./bareruby emulate "$sample" \
         "--target=$TARGET" --for=1 "${arguments[@]}" \
         </dev/null >"$kept/emulate.log" 2>&1; then
        printf '%-22s FAIL (emulate refused; %s)\n' "$name" "$kept/emulate.log"
        failed=$((failed + 1))
        continue
    fi

    if [ -n "$feed_path" ]; then
        awk 'FNR == NR { feed = feed $0 ORS; next }
             /^emulation RunFor / { printf "%s", feed; next }
             { print }' "$feed_path" ".bareruby/emulate/$TARGET/run.resc" \
             >"$kept/feed.resc"
        rm -f ".bareruby/emulate/$TARGET/uart.log"
        XDG_CONFIG_HOME="$CONFIG_HOME" "$RENODE" --disable-xwt --console --plain \
            -e "include @$PWD/$kept/feed.resc" >"$kept/feed.log" 2>&1
        "$RUBY" -e '
          File.write(ARGV.fetch(1), File.binread(ARGV.fetch(0)).gsub("\r\n", "\n"))
        ' ".bareruby/emulate/$TARGET/uart.log" ".bareruby/emulate/$TARGET/uart.txt"
    fi

    if [ "$capture" = hex ]; then
        "$RUBY" -e '
          bytes = File.binread(ARGV.fetch(0)).bytes
          File.write(ARGV.fetch(1), bytes.map { |byte| format("%02X", byte) }.join(" ") + "\n")
        ' ".bareruby/emulate/$TARGET/uart.log" "$kept/uart.txt"
    else
        cp ".bareruby/emulate/$TARGET/uart.txt" "$kept/uart.txt"
    fi
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
done

echo "stm32 uart: $passed/$((passed + failed)) checks passed on $TARGET"
[ "$failed" -eq 0 ]
