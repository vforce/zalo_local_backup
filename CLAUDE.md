# Zalo media backup

`backup.sh` transforms Zalo's stored media into real `.mp4`/`.jpg` files and pushes them to two remote folders on the same host.

## Setup (first time)

macOS only. From a clone of this repo:

1. **Install tools:** `brew install jpeg-xl ffmpeg rsync` — gives `djxl`, `ffprobe`, and brew's rsync 3.x (the macOS system `openrsync` lacks the flags this uses).
2. **Passwordless SSH** to your backup server (the script never types a password):
   ```bash
   ssh-copy-id user@host      # one-time; skip if key-based SSH already works
   ```
3. **Fill in your config:**
   ```bash
   cp .env.example .env
   ```
   Then edit `.env`:
   - `ZALO_ACCOUNT_ID` — your account's numeric folder. Find it with `ls ~/Library/Application\ Support/ZaloData/media/` (it's the one long number).
   - `HOST` — the `user@server` you just set up SSH for.
   - `DEST1`, `DEST2` — two folders on that server to back into (created automatically if missing).
4. **Inspect before uploading** (recommended the first time):
   ```bash
   ./backup.sh stage          # builds ./staging locally, uploads nothing
   ```
5. **Run it:** `./backup.sh`

`SRC`, `STAGE`, and the `rsync` binary are derived automatically — nothing else to configure.

## Run

```bash
./backup.sh all      # stage + upload + mirror (default)
./backup.sh stage    # build local staging only (inspect before uploading)
./backup.sh push     # upload existing staging + mirror
```

Re-runs are incremental and safe to repeat — only new/changed media transfers.

## What it does

- **Videos** (`ZaloDownloads/video/` — loose files + `group/`): extensionless MP4 containers. `ffprobe` detects the real format, then each is **hardlinked** under a `.mp4` name. Hardlink = real file, zero extra disk (shares bytes with the original).
- **Photos** (`ZaloDownloads/picture/<chat-id>/`): `.jxl` (JPEG XL) decoded to `.jpg` via `djxl`; existing `.jpg` hardlinked through.
- Uploads once to `dest1`, then mirrors `dest1 → dest2` **on the remote** (no double upload).
- Non-media junk (`.DS_Store`, `.rescache`) is skipped.

## Config

All per-machine settings live in `.env` (gitignored — copy `.env.example`, see [Setup](#setup-first-time)). `SRC`, `STAGE`, and the `rsync` path are derived in `backup.sh` (staging lives beside the script; `rsync` falls back Apple-Silicon → Intel → PATH).

## Zalo quirks handled (don't "simplify" these away)

- Some photos exist as **both** `foo.jxl` and `foo.jpg` at *different resolutions*. Both are kept — the decoded jxl lands at `foo.jxl.jpg` so it never clobbers the passthrough `foo.jpg`.
- A few `.jxl` files are actually JPEG bytes (mislabeled); `djxl` refuses them, so they're hardlinked as-is.

## Disk

Staging costs only the decoded JPEGs on disk (~7 GB); videos/existing-jpgs are hardlinks (free). Safe to `rm -rf staging` after a run — `rsync --size-only` means the next run re-decodes locally but does **not** re-upload unchanged files.

## Verify

Counts must match across all three:

```bash
source .env
find staging -type f | wc -l
ssh "$HOST" "find '$DEST1' -type f | wc -l"
ssh "$HOST" "find '$DEST2' -type f | wc -l"
```

Your counts will differ from the source author's — for reference, their full run was **20,126 files** (1,781 mp4 + 17,417 jpg + 926 jxl.jpg).
