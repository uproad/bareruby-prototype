#!/usr/bin/env bash
# Pack this directory into a .vsix, which is the one form VS Code installs from.
#
#     ./vscode/package.sh
#     code --install-extension vscode/bareruby-visualizer-0.0.1.vsix
#
# **A .vsix is a zip with two manifests beside the extension**, and nothing here is
# compiled — the files go in as they are. That is why this is a page rather than a
# toolchain: `vsce` exists to do this and a great deal else, none of which a throwaway
# needs.
#
# The archive itself is written by `python3`, because Ruby ships no zip writer and this
# desk has no `zip`. It is the one thing here that is neither Ruby nor JavaScript, and it
# is four lines long.
#
# Under a remote connection the install lands on the remote side, which is where this
# extension has to be: it starts a process in the project and reads the project's files.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$ROOT"

VERSION=$(ruby -rjson -e 'puts JSON.parse(File.read("package.json"))["version"]')
OUT="bareruby-visualizer-$VERSION.vsix"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/extension/media"
cp package.json extension.js watch.rb README.md "$WORK/extension/"
cp media/panel.html "$WORK/extension/media/"

cat > "$WORK/extension.vsixmanifest" <<XML
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="bareruby-visualizer" Version="$VERSION" Publisher="bareruby" />
    <DisplayName>BareRuby machine visualizer</DisplayName>
    <Description xml:space="preserve">Shows what the hosted machine's peripherals did while a program ran.</Description>
    <Tags>bareruby</Tags>
    <Categories>Visualization</Categories>
    <GalleryFlags>Public</GalleryFlags>
    <Properties>
      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.85.0" />
      <Property Id="Microsoft.VisualStudio.Code.ExtensionKind" Value="workspace" />
    </Properties>
  </Metadata>
  <Installation>
    <InstallationTarget Id="Microsoft.VisualStudio.Code" />
  </Installation>
  <Dependencies/>
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true" />
  </Assets>
</PackageManifest>
XML

cat > "$WORK/[Content_Types].xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="json" ContentType="application/json"/>
  <Default Extension="js" ContentType="application/javascript"/>
  <Default Extension="html" ContentType="text/html"/>
  <Default Extension="rb" ContentType="text/plain"/>
  <Default Extension="md" ContentType="text/markdown"/>
  <Default Extension="vsixmanifest" ContentType="text/xml"/>
</Types>
XML

rm -f "$ROOT/$OUT"
python3 - "$ROOT/$OUT" "$WORK" <<'PACKING'
import os, sys, zipfile

out, work = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as vsix:
    for base, _, names in os.walk(work):
        for name in names:
            whole = os.path.join(base, name)
            vsix.write(whole, os.path.relpath(whole, work))
PACKING

echo "$OUT"
