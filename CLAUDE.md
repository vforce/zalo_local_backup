# Zalo media backup

`backup.sh` transforms Zalo's stored media into real `.mp4`/`.jpg` files and pushes them to two remote folders on the same host.

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

Per-machine config lives in `.env` (gitignored). To set up on a new machine:

```bash
cp .env.example .env   # then fill in the four values
```

- `ZALO_ACCOUNT_ID` — numeric folder from `ls ~/Library/Application\ Support/ZaloData/media/`
- `HOST` — SSH target (key-based, no password prompt: `ssh-copy-id user@host`)
- `DEST1`, `DEST2` — two destination folders on that server

`SRC`, `STAGE`, and the `rsync` path are derived automatically in `backup.sh` (staging lives beside the script; `rsync` falls back Apple-Silicon → Intel → PATH).

## Dependencies

`brew install jpeg-xl ffmpeg rsync` — needs `djxl`, `ffprobe`, and brew's `rsync 3.x` (macOS system `openrsync` lacks the flags).

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

Last full run: **20,126 files** on both remotes (1,781 mp4 + 17,417 jpg + 926 jxl.jpg).
