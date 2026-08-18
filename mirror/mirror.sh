#!/usr/bin/env bash
# Checks Darkglass's "latest" download endpoint and archives the installer
# under archive/ if it's a version we don't already have. Meant to be run
# nightly from cron so that installers for versions Darkglass has since
# superseded (and stopped serving) are still around later - build.sh's
# per-version patches can only be added after the fact.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
SOFTWARE_IDS=(1)

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [darkglass-mirror] $*"
}

mkdir -p "$ARCHIVE_DIR"

for id in "${SOFTWARE_IDS[@]}"; do
  URL="https://api-v2.darkglass.com/product/software/download/latest?softwareId=$id"

  HEADERS="$(curl -sI -L "$URL")"
  FILENAME="$(echo "$HEADERS" | grep -i '^content-disposition:' | sed -E 's/.*filename="([^"]+)".*/\1/' | tr -d '\r')"

  if [ -z "$FILENAME" ]; then
    log "error: could not determine installer filename for softwareId=$id - endpoint may have changed"
    exit 1
  fi

  DEST="$ARCHIVE_DIR/$FILENAME"

  if [ -f "$DEST" ]; then
    continue
  fi

  log "new version detected for softwareId=$id: $FILENAME"
  curl -sS -L -o "$DEST.partial" "$URL"

  if [ ! -s "$DEST.partial" ]; then
    log "error: download for $FILENAME came back empty, discarding"
    rm -f "$DEST.partial"
    exit 1
  fi

  mv "$DEST.partial" "$DEST"
  log "archived: $DEST ($(du -h "$DEST" | cut -f1))"
done
