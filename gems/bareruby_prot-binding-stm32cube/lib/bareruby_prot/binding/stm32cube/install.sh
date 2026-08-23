#!/usr/bin/env bash
# Install everything sources.lock.yml pins, under the project's .tools/.
#
#     install.sh [FAMILY...]        # default: every family in the lock
#     install.sh --data [FAMILY...] # also the upstream pin data the update tooling reads
#
# Run from the project root — like every build, what this touches belongs to the desk it
# is run from, and all of it lands under ./.tools/. Nothing is fetched twice: a
# directory that already exists at its pinned version is left alone, so running this
# again after a lock change installs only what changed. No ST account, no `latest`:
# archives are verified by SHA-256 and repositories by commit before anything is used.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOCK="$HERE/data/sources.lock.yml"
TOOLS="$PWD/.tools"

RUBY=${RUBY:-ruby}
command -v "$RUBY" >/dev/null || {
    echo "bareruby: no ruby on PATH to read $LOCK with" >&2
    exit 1
}

WITH_DATA=0
FAMILIES=()
for argument in "$@"; do
    case "$argument" in
        --data) WITH_DATA=1 ;;
        *) FAMILIES+=("$argument") ;;
    esac
done

# --- host --------------------------------------------------------------------------

case "$(uname -s)" in
    Linux) OS=linux ;;
    Darwin) OS=darwin ;;
    *)
        echo "bareruby: no pinned binaries for $(uname -s)" >&2
        exit 1
        ;;
esac
case "$(uname -m)" in
    x86_64) CPU=x64 ;;
    aarch64 | arm64) CPU=arm64 ;;
    *)
        echo "bareruby: no pinned binaries for $(uname -m)" >&2
        exit 1
        ;;
esac
PLATFORM="$OS-$CPU"

# --- the lock, flattened -----------------------------------------------------------

# One line per thing to install, tab-separated. bash stays the executor; what to
# execute is the lock's answer, read by the same parser every Ruby side uses.
plan() {
    "$RUBY" -ryaml -e '
        lock = YAML.safe_load_file(ARGV[0])
        platform = ARGV[1]
        families = ARGV[2].split(",").reject(&:empty?)
        families = lock["families"].keys if families.empty?

        lock["common"].each do |name, tool|
          archive = tool.dig("archives", platform) or
            abort "bareruby: #{name} has no archive pinned for #{platform}"
          url = "https://github.com/#{tool["github"]}/releases/download/#{tool["release"]}/#{archive["file"]}"
          puts ["archive", name, tool["directory"], url, archive["sha256"]].join("\t")
        end

        # The emulator is wanted only by `bareruby emulate`, so a platform it is not
        # pinned for is a note rather than a stop: every build input still arrives.
        (lock["emulate"] || {}).each do |name, tool|
          archive = tool.dig("archives", platform)
          unless archive
            warn "bareruby: #{name} is not pinned for #{platform}; `bareruby emulate` stays uninstalled"
            next
          end
          url = "https://github.com/#{tool["github"]}/releases/download/#{tool["release"]}/#{archive["file"]}"
          puts ["archive", name, tool["directory"], url, archive["sha256"]].join("\t")
        end

        families.each do |family|
          entry = lock["families"][family] or
            abort "bareruby: the lock pins no family called #{family.inspect}"
          cube = entry["cube"]
          submodules = (cube["submodules"] || {}).map { |path, commit| "#{path}=#{commit}" }.join(",")
          puts ["repository", "#{family} SDK", cube["directory"],
                "https://github.com/#{cube["github"]}.git", cube["commit"],
                cube["tag"], submodules].join("\t")
          next unless ENV["WITH_DATA"] == "1"

          data = entry["open_pin_data"]
          puts ["repository", "#{family} pin data", data["directory"],
                "https://github.com/#{data["github"]}.git", data["commit"], "", ""].join("\t")
        end
    ' "$LOCK" "$PLATFORM" "$(IFS=,; echo "${FAMILIES[*]-}")"
}

# --- the two ways a thing arrives --------------------------------------------------

fetch_archive() {
    local name=$1 directory=$2 url=$3 sha256=$4
    local home="$TOOLS/$directory"
    if [ -d "$home" ]; then
        echo "bareruby: $name is already at $home"
        return
    fi

    echo "bareruby: fetching $name"
    local staging
    staging=$(mktemp -d "${TMPDIR:-/tmp}/bareruby-install.XXXXXX")
    trap 'rm -rf "$staging"' RETURN
    curl --fail --location --silent --show-error -o "$staging/archive" "$url"
    echo "$sha256  $staging/archive" | shasum -a 256 -c - >/dev/null 2>&1 ||
        echo "$sha256  $staging/archive" | sha256sum -c - >/dev/null || {
        echo "bareruby: $name does not match its pinned SHA-256; refusing it" >&2
        exit 1
    }
    mkdir -p "$staging/tree"
    tar -xzf "$staging/archive" -C "$staging/tree"
    local unpacked
    unpacked=$(find "$staging/tree" -mindepth 1 -maxdepth 1 -type d)
    [ "$(printf '%s\n' "$unpacked" | wc -l)" -eq 1 ] || {
        echo "bareruby: $name unpacked into more than one directory; refusing it" >&2
        exit 1
    }
    mkdir -p "$(dirname "$home")"
    mv "$unpacked" "$home"
    echo "bareruby: $name -> $home"
}

fetch_repository() {
    local name=$1 directory=$2 url=$3 commit=$4 tag=$5 submodules=$6
    local home="$TOOLS/$directory"
    if [ -d "$home" ]; then
        local found
        found=$(git -C "$home" rev-parse HEAD 2>/dev/null || echo none)
        if [ "$found" = "$commit" ]; then
            echo "bareruby: $name is already at $home ($tag)"
            return
        fi
        echo "bareruby: $home is at $found, not the pinned $commit; refusing to touch it" >&2
        exit 1
    fi

    echo "bareruby: cloning $name"
    mkdir -p "$(dirname "$home")"
    if [ -n "$tag" ]; then
        git clone --quiet --depth 1 --branch "$tag" "$url" "$home"
    else
        # Pinned by commit alone: fetch exactly that commit.
        git init --quiet "$home"
        git -C "$home" remote add origin "$url"
        git -C "$home" fetch --quiet --depth 1 origin "$commit"
        git -C "$home" checkout --quiet FETCH_HEAD
    fi
    local found
    found=$(git -C "$home" rev-parse HEAD)
    [ "$found" = "$commit" ] || {
        echo "bareruby: $name checked out $found, not the pinned $commit; refusing it" >&2
        exit 1
    }

    local pair path pinned
    for pair in ${submodules//,/ }; do
        path=${pair%%=*}
        pinned=${pair##*=}
        git -C "$home" submodule update --quiet --init --depth 1 -- "$path" 2>/dev/null ||
            git -C "$home" submodule update --quiet --init -- "$path"
        found=$(git -C "$home/$path" rev-parse HEAD)
        [ "$found" = "$pinned" ] || {
            echo "bareruby: $name submodule $path is $found, not the pinned $pinned" >&2
            exit 1
        }
    done
    echo "bareruby: $name -> $home ($tag)"
}

# --- run ---------------------------------------------------------------------------

while IFS=$'\t' read -r kind name directory url pin tag submodules; do
    case "$kind" in
        archive) fetch_archive "$name" "$directory" "$url" "$pin" ;;
        repository) fetch_repository "$name" "$directory" "$url" "$pin" "$tag" "$submodules" ;;
    esac
done < <(WITH_DATA=$WITH_DATA plan)

# --- prove it ----------------------------------------------------------------------

GCC_HOME=$("$RUBY" -ryaml -e 'puts YAML.safe_load_file(ARGV[0]).dig("common", "arm_gcc", "directory")' "$LOCK")
"$TOOLS/$GCC_HOME/bin/arm-none-eabi-gcc" --version | head -1
OPENOCD_HOME=$("$RUBY" -ryaml -e 'puts YAML.safe_load_file(ARGV[0]).dig("common", "openocd", "directory")' "$LOCK")
"$TOOLS/$OPENOCD_HOME/bin/openocd" --version 2>&1 | head -1
RENODE_HOME=$("$RUBY" -ryaml -e 'puts YAML.safe_load_file(ARGV[0]).dig("emulate", "renode", "directory").to_s' "$LOCK")
if [ -n "$RENODE_HOME" ] && [ -x "$TOOLS/$RENODE_HOME/renode" ]; then
    "$TOOLS/$RENODE_HOME/renode" --version 2>/dev/null | head -1
fi
echo "bareruby: installed under $TOOLS"
