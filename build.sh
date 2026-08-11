#!/usr/bin/env bash
# Builds a native-Linux Darkglass Suite AppImage from Darkglass's own
# published Windows installer.
#
# Usage: ./build.sh [output-path]
#   output-path defaults to ./Darkglass-Suite-<version>-x86_64.AppImage,
#   relative to the directory this script is invoked FROM (not this
#   script's own location).
set -euo pipefail

ORIGINAL_PWD="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHES_DIR="$SCRIPT_DIR/patches"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
DOWNLOAD_DIR="$SCRIPT_DIR/cache"
TOOLS_DIR="$DOWNLOAD_DIR/tools"
DOWNLOAD_URL="https://api-v2.darkglass.com/product/software/download/latest?softwareId=1"

PRETTIER_VERSION="3.4.2"
NODE_GYP_VERSION="10"
NODE_ADDON_API_VERSION="8.9.1"
APPIMAGETOOL_VERSION="1.9.1"
APPIMAGETOOL="$TOOLS_DIR/appimagetool-$APPIMAGETOOL_VERSION-x86_64.AppImage"
TYPE2_RUNTIME_VERSION="20251108"
TYPE2_RUNTIME="$TOOLS_DIR/type2-runtime-$TYPE2_RUNTIME_VERSION-x86_64"

electron_version_for() {
  case "$1" in
    6.8.0-rc10) echo "35.7.5" ;;
    *) echo "" ;;
  esac
}

for cmd in curl 7z npx node gcc dos2unix; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "error: required command '$cmd' not found" >&2; exit 1; }
done

if [ ! -f "$APPIMAGETOOL" ]; then
  echo "==> Downloading appimagetool $APPIMAGETOOL_VERSION (cached under cache/tools/ from now on) ..."
  mkdir -p "$TOOLS_DIR"
  curl -L -o "$APPIMAGETOOL.partial" \
    "https://github.com/AppImage/appimagetool/releases/download/$APPIMAGETOOL_VERSION/appimagetool-x86_64.AppImage"
  mv "$APPIMAGETOOL.partial" "$APPIMAGETOOL"
  chmod +x "$APPIMAGETOOL"
fi

if [ ! -f "$TYPE2_RUNTIME" ]; then
  echo "==> Downloading AppImage type2-runtime $TYPE2_RUNTIME_VERSION (cached under cache/tools/ from now on) ..."
  mkdir -p "$TOOLS_DIR"
  curl -L -o "$TYPE2_RUNTIME.partial" \
    "https://github.com/AppImage/type2-runtime/releases/download/$TYPE2_RUNTIME_VERSION/runtime-x86_64"
  mv "$TYPE2_RUNTIME.partial" "$TYPE2_RUNTIME"
  chmod +x "$TYPE2_RUNTIME"
fi

# Step 1+2: figure out the latest version and check it's one we
# support, before downloading anything

echo "==> Checking latest Darkglass Suite version..."
HEADERS="$(curl -sI -L "$DOWNLOAD_URL")"
FILENAME="$(echo "$HEADERS" | grep -i '^content-disposition:' | sed -E 's/.*filename="([^"]+)".*/\1/' | tr -d '\r')"

if [ -z "$FILENAME" ]; then
  echo "error: could not determine the installer filename from the download endpoint's response." >&2
  echo "       the endpoint or its response shape may have changed:" >&2
  echo "       $DOWNLOAD_URL" >&2
  exit 1
fi

VERSION="$(echo "$FILENAME" | sed -E 's/^Darkglass Suite-(.+)-x64\.exe$/\1/')"
echo "    latest version: $VERSION (installer: $FILENAME)"

ELECTRON_VERSION="$(electron_version_for "$VERSION")"
PATCH_MAIN="$PATCHES_DIR/main.js.$VERSION.patch"
PATCH_RENDERER="$PATCHES_DIR/renderer.prod.js.$VERSION.patch"
PATCH_FIOS="$PATCHES_DIR/libfios-serial.c.$VERSION.patch"

if [ -z "$ELECTRON_VERSION" ] || [ ! -f "$PATCH_MAIN" ] || [ ! -f "$PATCH_RENDERER" ] || [ ! -f "$PATCH_FIOS" ]; then
  echo "error: Darkglass Suite $VERSION has not been validated against this script." >&2
  echo "       Refusing to proceed automatically - patches are hand-verified per" >&2
  echo "       version and may not apply cleanly (or could silently misapply) against" >&2
  echo "       an untested release. Versions currently supported:" >&2
  for f in "$PATCHES_DIR"/main.js.*.patch; do
    [ -f "$f" ] || continue
    v="${f#"$PATCHES_DIR"/main.js.}"
    v="${v%.patch}"
    echo "         $v" >&2
  done
  echo "       See README.md for how to add support for a new version." >&2
  exit 1
fi
echo "    supported - pinned Electron version: $ELECTRON_VERSION"

# Step 3: download (reusing an existing copy if present) and extract
# the NSIS installer directly with 7z.

mkdir -p "$DOWNLOAD_DIR"
INSTALLER_PATH="$DOWNLOAD_DIR/$FILENAME"

if [ -f "$INSTALLER_PATH" ]; then
  echo "==> Reusing already-downloaded installer at $INSTALLER_PATH"
else
  echo "==> Downloading $FILENAME to $DOWNLOAD_DIR ..."
  curl -L -o "$INSTALLER_PATH.partial" "$DOWNLOAD_URL"
  mv "$INSTALLER_PATH.partial" "$INSTALLER_PATH"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Extracting installer (NSIS outer layer) ..."
7z x "$INSTALLER_PATH" -o"$WORK/nsis" -y > /dev/null

echo "==> Extracting app payload (nested 7z) ..."
7z x "$WORK/nsis/\$PLUGINSDIR/app-64.7z" -o"$WORK/payload" -y > /dev/null

ASAR="$WORK/payload/resources/app.asar"
if [ ! -f "$ASAR" ]; then
  echo "error: expected $ASAR after extraction, not found. Installer layout may have changed." >&2
  exit 1
fi

# Step 4: extract the asar.
echo "==> Extracting app.asar ..."
npx --yes asar extract "$ASAR" "$WORK/app" > /dev/null

# Step 5: apply our patches

echo "==> Patching main.js ..."
npx --yes prettier@"$PRETTIER_VERSION" --parser babel "$WORK/app/main.js" > "$WORK/main.js.pretty"
( cd "$WORK" && patch -p1 < "$PATCH_MAIN" )
mv "$WORK/main.js.pretty" "$WORK/app/main.js"
node --check "$WORK/app/main.js"

echo "==> Patching renderer.prod.js ..."
npx --yes prettier@"$PRETTIER_VERSION" --parser babel "$WORK/app/dist/renderer.prod.js" > "$WORK/renderer.prod.js.pretty"
( cd "$WORK" && patch -p1 < "$PATCH_RENDERER" )
mv "$WORK/renderer.prod.js.pretty" "$WORK/app/dist/renderer.prod.js"
node --check "$WORK/app/dist/renderer.prod.js"

echo "==> Patching fios's serial code ..."
dos2unix -q "$WORK/app/node_modules/fios/src/libfios-serial.c"
( cd "$WORK/app" && patch -p1 < "$PATCH_FIOS" )
cp "$TEMPLATES_DIR/fios-binding.gyp" "$WORK/app/node_modules/fios/binding.gyp"

# Step 6: compile fios.node for Linux, against the pinned Electron ABI

echo "==> Compiling fios.node for Linux (Electron $ELECTRON_VERSION ABI) ..."
( cd "$WORK/app/node_modules/fios" && \
  npm install node-addon-api@"$NODE_ADDON_API_VERSION" --no-save --silent && \
  npx --yes node-gyp@"$NODE_GYP_VERSION" rebuild \
    --target="$ELECTRON_VERSION" --arch=x64 \
    --dist-url=https://electronjs.org/headers )

FIOS_NODE="$WORK/app/node_modules/fios/build/Release/fios.node"
if ! file "$FIOS_NODE" | grep -q "ELF"; then
  echo "error: fios.node did not build as a Linux ELF binary" >&2
  exit 1
fi

# Step 7: assemble an AppDir

APP="$WORK/AppDir/usr"
echo "==> Assembling AppDir ..."
mkdir -p "$APP/resources"
cp -r "$WORK/app" "$APP/resources/app"
cp -r "$WORK/payload/resources/assets" "$APP/resources/assets"
cp "$WORK/payload/resources/app-update.yml" "$APP/resources/app-update.yml"
if [ -d "$WORK/nsis/resources/assets" ]; then
  cp -rn "$WORK/nsis/resources/assets/." "$APP/resources/assets/"
fi

cat > "$APP/package.json" <<EOF
{
  "name": "darkglass-suite-linux",
  "version": "$VERSION",
  "private": true,
  "description": "Unofficial Linux build of Darkglass Suite $VERSION. Not for redistribution.",
  "main": "boot.js",
  "devDependencies": {
    "electron": "$ELECTRON_VERSION"
  }
}
EOF

cp "$TEMPLATES_DIR/boot.js" "$APP/boot.js"

echo "==> Installing Electron $ELECTRON_VERSION ..."
( cd "$APP" && npm install --silent )

# Step 8: package as a single-file AppImage

echo "==> Packaging AppImage ..."
cp "$TEMPLATES_DIR/AppRun" "$WORK/AppDir/AppRun"
chmod +x "$WORK/AppDir/AppRun"
cp "$TEMPLATES_DIR/darkglass-suite.desktop" "$WORK/AppDir/darkglass-suite.desktop"
cp "$APP/resources/assets/icons/icon-512x512.png" "$WORK/AppDir/darkglass-suite.png"

OUTPUT_PATH="${1:-$ORIGINAL_PWD/Darkglass-Suite-$VERSION-x86_64.AppImage}"
ARCH=x86_64 "$APPIMAGETOOL" --runtime-file "$TYPE2_RUNTIME" "$WORK/AppDir" "$OUTPUT_PATH"

echo
echo "Build complete: $OUTPUT_PATH"
