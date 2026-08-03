#!/usr/bin/env bash
# Synchronize one generated program into a user-owned CubeIDE project and build it.
#
#     cube.sh TARGET_DIRECTORY PROJECT_DIRECTORY CONFIGURATION
#
# The CubeIDE project owns reset, clocks, peripheral initialization, the linker script
# and the final link. Only the translation units this program reached for are copied in,
# and only files this bridge owns are replaced.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)

TARGET_DIRECTORY=$1
PROJECT_DIRECTORY=$2
CONFIGURATION=${3:-Debug}

TOOLS="$ROOT/.tools/stm32cube"

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

GENERATED_HEADERS=(
    "$ROOT/build/bareruby_binding.h"
    "$ROOT/build/bareruby_runtime.h"
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

echo "bareruby: synchronized generated sources into $PROJECT_NAME"

find_cubeide() {
    if [ -n "${STM32CUBEIDE:-}" ]; then
        if [ -x "$STM32CUBEIDE" ]; then
            printf '%s\n' "$STM32CUBEIDE"
            return
        fi
        echo "bareruby: STM32CUBEIDE is not executable: $STM32CUBEIDE" >&2
        return 1
    fi

    # What this repository keeps comes first, then what the desk installed for itself.
    local candidate
    for candidate in "$TOOLS"/stm32cubeide_*/headless-build.sh \
                     "$TOOLS"/stm32cubeide_*/stm32cubeide \
                     "$(command -v headless-build.sh || true)" \
                     "$(command -v stm32cubeide || true)" \
                     /opt/st/stm32cubeide_*/headless-build.sh \
                     /opt/st/stm32cubeide_*/stm32cubeide; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return
        fi
    done
    return 1
}

if ! CUBEIDE=$(find_cubeide); then
    echo "bareruby: STM32CubeIDE was not found. Set STM32CUBEIDE." >&2
    exit 1
fi

if [ -z "${STM32CUBEIDE_WORKSPACE:-}" ]; then
    project_checksum=$(printf '%s\n' "$PROJECT_DIRECTORY" | cksum)
    project_checksum=${project_checksum%% *}
    STM32CUBEIDE_WORKSPACE="$TOOLS/workspace/$PROJECT_NAME-$project_checksum"
fi
if [ -z "${STM32CUBEIDE_CONFIGURATION:-}" ]; then
    ide_checksum=$(printf '%s\n' "$CUBEIDE" | cksum)
    ide_checksum=${ide_checksum%% *}
    STM32CUBEIDE_CONFIGURATION="$TOOLS/configuration/$ide_checksum"
fi
mkdir -p "$STM32CUBEIDE_WORKSPACE" "$STM32CUBEIDE_CONFIGURATION"

echo "bareruby: build ($PROJECT_NAME/$CONFIGURATION)"
if [ "$(basename "$CUBEIDE")" = headless-build.sh ]; then
    "$CUBEIDE" -configuration "$STM32CUBEIDE_CONFIGURATION" \
        -data "$STM32CUBEIDE_WORKSPACE" -import "$PROJECT_DIRECTORY" \
        -cleanBuild "$PROJECT_NAME/$CONFIGURATION"
else
    "$CUBEIDE" --launcher.suppressErrors -nosplash \
        -application org.eclipse.cdt.managedbuilder.core.headlessbuild \
        -configuration "$STM32CUBEIDE_CONFIGURATION" \
        -data "$STM32CUBEIDE_WORKSPACE" -import "$PROJECT_DIRECTORY" \
        -cleanBuild "$PROJECT_NAME/$CONFIGURATION"
fi

ARTIFACT="$PROJECT_DIRECTORY/$CONFIGURATION/$PROJECT_NAME.elf"
[ -f "$ARTIFACT" ] || {
    echo "bareruby: CubeIDE completed without producing $ARTIFACT" >&2
    exit 1
}

# The firmware comes back beside the sources it was made from, so that flashing needs to
# know nothing about where the external project keeps its output.
install -m 0644 "$ARTIFACT" "$TARGET_DIRECTORY/bareruby_program.elf"
echo "bareruby: firmware: $TARGET_DIRECTORY/bareruby_program.elf"
