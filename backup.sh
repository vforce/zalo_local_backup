#!/usr/bin/env bash
# Transform Zalo media into real .mp4 / .jpg files and back them up to two remote folders.
#   usage: ./backup.sh [stage|push|all]     (default: all)
#     stage  build the staging tree only (local, safe to inspect before uploading)
#     push   upload the staging tree to both remotes
#     all    stage then push
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/.env" ] || { echo "missing $HERE/.env — run: cp .env.example .env  (then fill it in)" >&2; exit 1; }
source "$HERE/.env"

# Derived — no need to configure. SRC is your Zalo folder; STAGE lives beside this script.
SRC="$HOME/Library/Application Support/ZaloData/media/$ZALO_ACCOUNT_ID/ZaloDownloads"
STAGE="$HERE/staging"
DESTS=("$DEST1" "$DEST2")
JOBS="${JOBS:-6}"
RSYNC="${RSYNC:-/opt/homebrew/bin/rsync}"   # 3.4.1; macOS system "openrsync" lacks --info/--partial
[ -x "$RSYNC" ] || RSYNC=/usr/local/bin/rsync   # Intel Homebrew
[ -x "$RSYNC" ] || RSYNC=rsync                   # last resort: whatever's on PATH

command -v djxl >/dev/null    || { echo "need djxl: brew install jpeg-xl" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "need ffprobe: brew install ffmpeg" >&2; exit 1; }
export SRC STAGE

build_stage() {
  echo ">> staging into $STAGE"

  # Videos are extensionless containers -> ask ffprobe the real format, hardlink under the right ext.
  # Same volume, so a hardlink is a real file (opens/rsyncs like any other) at zero extra disk.
  # ffprobe returns empty for non-media (.DS_Store, junk) -> skipped automatically.
  find "$SRC/video" -type f ! -name '.rescache' ! -name '.DS_Store' -print0 |
  xargs -0 -P "$JOBS" -I{} bash -c '
    f="$1"; rel="${f#$SRC/}"
    compgen -G "$STAGE/$rel.*" >/dev/null 2>&1 && exit 0   # already staged under some ext -> skip probe
    case "$(ffprobe -v error -show_entries format=format_name -of csv=p=0 "$f" 2>/dev/null)" in
      "")                exit 0 ;;                # not media -> skip
      *matroska*|*webm*) ext=webm ;;
      *mp4*|*mov*|*m4a*) ext=mp4  ;;
      gif)               ext=gif  ;;
      avi)               ext=avi  ;;
      *)                 ext=mp4  ;;              # some other real container -> default mp4
    esac
    out="$STAGE/$rel.$ext"; mkdir -p "${out%/*}"; ln "$f" "$out"
  ' _ {}

  # Existing .jpg -> pass through as a hardlink (already the native format).
  find "$SRC/picture" -type f -name '*.jpg' -print0 |
  while IFS= read -r -d '' f; do
    out="$STAGE/${f#$SRC/}"
    mkdir -p "${out%/*}"; [ -e "$out" ] || ln "$f" "$out"
  done

  # .jxl (JPEG XL) -> decode to a real .jpg. Idempotent: skip if already decoded.
  # Two Zalo quirks handled:
  #   - some ".jxl" are actually JPEG bytes (djxl refuses) -> hardlink as-is.
  #   - some photos exist as BOTH foo.jxl and foo.jpg at DIFFERENT resolutions -> keep both;
  #     the decoded jxl lands at foo.jxl.jpg so it never clobbers the passthrough foo.jpg.
  local n; n=$(find "$SRC/picture" -type f -name '*.jxl' | wc -l | tr -d ' ')
  echo ">> decoding $n jxl -> jpg with $JOBS workers (this is the slow part)…"
  find "$SRC/picture" -type f -name '*.jxl' -print0 |
  xargs -0 -P "$JOBS" -I{} bash -c '
    f="$1"; base="${f#$SRC/}"; base="${base%.jxl}"
    if [ -e "$SRC/$base.jpg" ]; then out="$STAGE/$base.jxl.jpg"; else out="$STAGE/$base.jpg"; fi
    mkdir -p "${out%/*}"
    [ -e "$out" ] && exit 0
    djxl "$f" "$out" >/dev/null 2>&1 && exit 0
    case "$(file -b "$f")" in JPEG*) ln "$f" "$out" ;; *) echo "FAIL $f" >&2 ;; esac
  ' _ {}
  echo ">> staging done: $(find "$STAGE" -type f -o -type l | wc -l | tr -d ' ') files"
}

push() {
  ssh "$HOST" "mkdir -p '${DESTS[0]}' '${DESTS[1]}'"
  echo ">> uploading to ${DESTS[0]}"
  # --size-only: staging is rebuilt fresh each run so decoded JPEGs get new mtimes, but djxl is
  # deterministic and Zalo names are content-hashed -> same size means same content, skip re-upload.
  "$RSYNC" -a --no-o --no-g --size-only --partial --info=progress2 "$STAGE/" "$HOST:${DESTS[0]}/"
  echo ">> mirroring to ${DESTS[1]} on the remote (local copy, no re-upload)"
  # remote-side rsync: incremental, additive. Add --delete if you want dest2 to exactly mirror dest1.
  ssh "$HOST" "rsync -a --no-o --no-g --size-only '${DESTS[0]}/' '${DESTS[1]}/'"
}

case "${1:-all}" in
  stage) build_stage ;;
  push)  push ;;
  all)   build_stage; push ;;
  *) echo "usage: $0 [stage|push|all]" >&2; exit 1 ;;
esac
echo ">> done"
