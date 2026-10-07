# bash-toolkit

Bash configuration + two small scripts I use daily:

| Script | What it does |
|---|---|
| [`bin/play`](bin/play) | Search YouTube and play audio-only. Keeps going with the related mix, like YouTube's "up next". |
| [`bin/laptop-health.sh`](bin/laptop-health.sh) | One-shot system health report: temps, RAM, swap, SSD SMART, battery, disk, protective services. |

## Layout

```
.
├── .bashrc                  # shell config (sourced at startup)
├── bin/
│   ├── play                 # YouTube audio player
│   └── laptop-health.sh     # health report
├── install.sh               # symlinks the files into $HOME
├── .gitignore
└── README.md
```

## Install

```bash
git clone https://github.com/hariomop12/bash-toolkit.git ~/.bash-toolkit
cd ~/.bash-toolkit
./install.sh
```

Already installed and pulled changes? Just re-run `./install.sh` — it's idempotent and will only re-link what changed.

### Options

| Flag | Effect |
|---|---|
| `--dry-run` | Print what it *would* do, change nothing |
| `--force` | Overwrite existing files without keeping a backup |

Anything it replaces is first copied to `~/.dotfiles-backup/<timestamp>/`.

> **Don't run with `sudo`.** It refuses to, because `sudo` would leave root-owned files in your home directory.

## Usage

### `play`

```bash
play                  # usage
play tum hi ho        # search, play, then keep going
```

**Dependencies:** `sudo apt install yt-dlp mpv`

The script finds the best match for your query, then asks `mpv` for that video's `RD`-mix (YouTube's related feed) capped at 50 tracks, so music continues without you searching again. If the direct search fails it falls back to a 25-result search playlist instead of erroring out.

### `laptop-health.sh`

```bash
health                 # full report
healthbrief            # one-line summary
laptop-health.sh --json     # machine-readable
laptop-health.sh --help     # usage
```

Checks CPU/GPU temperature, available RAM, swap usage, SSD life and media errors, root filesystem usage, battery level and health, and whether the protective services (`zram-swap`, `earlyoom`, `noc-monitor`) are both **running and enabled at boot**.

**Exit codes** — usable directly in shell logic:

| Code | Meaning |
|---|---|
| `0` | All healthy |
| `1` | Warnings, nothing critical |
| `2` | Critical — act now |
| `64` | Bad usage / unknown flag |

```bash
if healthbrief; then echo "all good"; else echo "needs attention"; fi
```

**Dependencies:** `lm-sensors`, `nvme-cli` (for SMART), `sudo` with a passwordless rule for `nvme smart-log` if you want SSD checks.

Output is colourised on a TTY and plain otherwise — set `NO_COLOR` to force it off.

## Customising

`.bashrc` is the only file the shell reads directly; `play` and `laptop-health.sh` live in `bin/` and are reached through `$HOME/bin` on `$PATH`. That split keeps the shell config small and makes each script independently testable and re-usable outside bash.

Edit anything, then `git diff` to see exactly what changed before committing.

## Notes

- `$HOME` is used throughout instead of `/home/<user>`, so nothing depends on a particular username.
- No secrets belong in this repo. Keep them in `~/.config/`, environment files outside version control, or a separate private store.
