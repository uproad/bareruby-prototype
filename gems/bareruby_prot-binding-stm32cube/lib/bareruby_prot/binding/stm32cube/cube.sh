#!/usr/bin/env bash
# Synchronize one generated program into a CubeMX project and build it.
#
#     cube.sh TARGET_DIRECTORY PROJECT_DIRECTORY CONFIGURATION
#
# The CubeMX project owns reset, clocks, peripheral initialization, the linker script and
# the startup file. Only the translation units this program reached for are copied in, and
# only files this bridge owns are replaced.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

TARGET_DIRECTORY=$1
PROJECT_DIRECTORY=$2
CONFIGURATION=${3:-Debug}

# Found from where the command was run rather than from where this script is. A binding
# that is not part of the checkout cannot reach out of its own directory and expect to
# land in one: an SDK and a CubeMX project belong to the desk, not to the gem that asks
# for them.
TOOLS="$PWD/.tools/stm32cube"

# CubeMX generates the project rather than this repository, but a build reaches for it,
# so it belongs where everything else a build reaches for is kept. One project there
# needs no naming. A desk that keeps several, or keeps its own somewhere else, says which
# in target.yml — the same shape as an SDK path in the environment.
if [ -z "$PROJECT_DIRECTORY" ]; then
    FOUND=()
    for candidate in "$TOOLS"/*/; do
        [ -f "$candidate.cproject" ] && FOUND+=("${candidate%/}")
    done
    case ${#FOUND[@]} in
        1) PROJECT_DIRECTORY=${FOUND[0]} ;;
        0)
            echo "bareruby: no CubeIDE project under $TOOLS" >&2
            echo "          Put one there, or name one as options.cube_project in target.yml." >&2
            exit 1
            ;;
        *)
            echo "bareruby: several CubeIDE projects under $TOOLS:" >&2
            printf '            %s\n' "${FOUND[@]##*/}" >&2
            echo "          Name one as options.cube_project in target.yml." >&2
            exit 1
            ;;
    esac
fi

PROJECT_DIRECTORY=$(realpath -m "$PROJECT_DIRECTORY")
[ -f "$PROJECT_DIRECTORY/.project" ] || {
    echo "bareruby: not a CubeIDE project: $PROJECT_DIRECTORY" >&2
    exit 1
}
[ -f "$PROJECT_DIRECTORY/.cproject" ] || {
    echo "bareruby: missing CubeIDE configuration: $PROJECT_DIRECTORY/.cproject" >&2
    exit 1
}
for required_directory in Core/Src Core/Inc; do
    [ -d "$PROJECT_DIRECTORY/$required_directory" ] || {
        echo "bareruby: missing project directory: $PROJECT_DIRECTORY/$required_directory" >&2
        exit 1
    }
done

PROJECT_NAME=""
while IFS= read -r project_line; do
    case "$project_line" in
        *'<name>'*'</name>'*)
            PROJECT_NAME=${project_line#*<name>}
            PROJECT_NAME=${PROJECT_NAME%%</name>*}
            break
            ;;
    esac
done < "$PROJECT_DIRECTORY/.project"
case "$PROJECT_NAME" in
    ""|.|..|*/*)
        echo "bareruby: could not read a safe project name from $PROJECT_DIRECTORY/.project" >&2
        exit 1
        ;;
esac

MAIN_SOURCE="$PROJECT_DIRECTORY/Core/Src/main.c"
[ -f "$MAIN_SOURCE" ] || {
    echo "bareruby: missing CubeMX entry source: $MAIN_SOURCE" >&2
    exit 1
}
if ! grep -q '#include "bareruby_entry.h"' "$MAIN_SOURCE" ||
   ! grep -q 'bareruby_entry();' "$MAIN_SOURCE"; then
    echo "bareruby: $MAIN_SOURCE is not connected to BareRuby" >&2
    echo "          Add bareruby_entry.h and bareruby_entry() in CubeMX USER CODE sections." >&2
    exit 1
fi

SOURCE_LIST="$TARGET_DIRECTORY/source-list.txt"
[ -f "$SOURCE_LIST" ] || {
    echo "bareruby: pass 12 did not emit $SOURCE_LIST" >&2
    exit 1
}

GENERATED_SOURCES=()
while IFS= read -r relative_source; do
    [ -n "$relative_source" ] || continue
    case "$relative_source" in
        bareruby_program.cpp) ;;
        ../bareruby_*.cpp)
            [ "${relative_source#../}" = "$(basename "$relative_source")" ] || {
                echo "bareruby: refusing unexpected generated path: $relative_source" >&2
                exit 1
            }
            ;;
        *)
            echo "bareruby: refusing unexpected generated path: $relative_source" >&2
            exit 1
            ;;
    esac

    generated_source=$(realpath "$TARGET_DIRECTORY/$relative_source")
    [ -f "$generated_source" ] || {
        echo "bareruby: generated source is missing: $generated_source" >&2
        exit 1
    }
    GENERATED_SOURCES+=("$generated_source")
done < "$SOURCE_LIST"

# The two headers are the first stage's output rather than anything this side carries, so
# they are found from what this run produced: they sit one level above the target's
# directory, which is the same place the source list reaches them at.
GENERATED=$(dirname "$TARGET_DIRECTORY")
GENERATED_HEADERS=(
    "$GENERATED/bareruby_binding.h"
    "$GENERATED/bareruby_runtime.h"
    "$HERE/bareruby_entry.h"
)
for generated_header in "${GENERATED_HEADERS[@]}"; do
    [ -f "$generated_header" ] || {
        echo "bareruby: generated header is missing: $generated_header" >&2
        exit 1
    }
done

# Files with this prefix are owned by this bridge. Validate every replacement before
# removing the previous set, and never touch CubeMX-generated or ordinary user files.
find "$PROJECT_DIRECTORY/Core/Src" -maxdepth 1 -type f -name 'bareruby_*.cpp' -delete
for generated_source in "${GENERATED_SOURCES[@]}"; do
    install -m 0644 "$generated_source" "$PROJECT_DIRECTORY/Core/Src/$(basename "$generated_source")"
done
for generated_header in "${GENERATED_HEADERS[@]}"; do
    install -m 0644 "$generated_header" "$PROJECT_DIRECTORY/Core/Inc/$(basename "$generated_header")"
done

install -m 0644 "$TARGET_DIRECTORY/Makefile" "$PROJECT_DIRECTORY/Makefile"

echo "bareruby: synchronized generated sources into $PROJECT_NAME"

# CubeMX generates sources, not a build. The build it names is STM32CubeIDE, an Eclipse
# application that cannot be had without an ST account — so what it would have compiled
# is compiled here instead, by the ARM GNU toolchain the freestanding boards already use.
TOOLCHAIN="${ARM_TOOLCHAIN_PATH:-$PWD/.tools/common/arm/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi}/bin/arm-none-eabi"
[ -x "$TOOLCHAIN-g++" ] || {
    echo "bareruby: no ARM toolchain at $TOOLCHAIN-g++" >&2
    echo "          Put one under .tools/, or name one in ARM_TOOLCHAIN_PATH." >&2
    exit 1
}

# A toolchain is chatty even when everything is fine, so its output is kept for the
# failure it explains and said nothing about otherwise.
echo "bareruby: build ($PROJECT_NAME/$CONFIGURATION)"
if ! BUILD_OUTPUT=$(make -C "$PROJECT_DIRECTORY" -j "$(nproc)" \
                        CONFIGURATION="$CONFIGURATION" TOOLCHAIN="$TOOLCHAIN" 2>&1); then
    printf '%s\n' "$BUILD_OUTPUT" >&2
    echo "bareruby: the second stage failed in $PROJECT_DIRECTORY" >&2
    exit 1
fi

ARTIFACT="$PROJECT_DIRECTORY/$CONFIGURATION/bareruby_program.elf"
[ -f "$ARTIFACT" ] || {
    echo "bareruby: the build completed without producing $ARTIFACT" >&2
    exit 1
}

# The firmware comes back beside the sources it was made from, so that flashing needs to
# know nothing about where the external project keeps its output.
install -m 0644 "$ARTIFACT" "$TARGET_DIRECTORY/bareruby_program.elf"
echo "bareruby: firmware: $TARGET_DIRECTORY/bareruby_program.elf"
