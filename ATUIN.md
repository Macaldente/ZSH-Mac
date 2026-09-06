# Atuin — install, keybindings, and importing legacy zsh history

Documentation for the [Atuin](https://github.com/atuinsh/atuin) shell-history
setup on this machine, and the exact procedure to reproduce it elsewhere.
Last verified: **2026-09-06** (macOS, zsh 5.9, arm64, atuin 18.19.0).

Two things here are non-obvious and cost real time to get right:

1. Atuin must **not** be installed as an Antidote plugin (§3).
2. If you forgot `atuin import auto` at install time, running it later is
   destructive — a filtered backfill is required instead (§4).

---

## 1. Layout

```
~/.atuin/bin/atuin              # binary (official installer; absent with Homebrew)
~/.atuin/bin/env                # prepends ~/.atuin/bin to $PATH
~/.local/share/atuin/history.db # SQLite history database (WAL mode)
~/.config/atuin/config.toml     # client config, if present
~/.zsh_history                  # zsh's own history — still written in parallel
```

Atuin does **not** replace `~/.zsh_history`; zsh keeps appending to it
independently. The two stores drift apart, which is what makes §4 necessary.

---

## 2. Install and activation

```sh
curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
atuin register -u <user> -e <email>   # or: atuin login -u <user>
atuin import auto                     # DO THIS NOW — see §4 if you forgot
```

Activation lives at the **end** of `~/.zshrc`, after `antidote load`:

```zsh
# Atuin: opt out of its default keymap so it cannot take the Up arrow away from
# zsh-autocomplete's history menu. Atuin keeps Ctrl+R only.
# ~/.atuin/bin/env only exists when atuin was installed via the official
# install script rather than Homebrew; guard it so Homebrew-only installs
# don't error on every shell start.
[ -f "$HOME/.atuin/bin/env" ] && . "$HOME/.atuin/bin/env"
export ATUIN_NOBIND=true
eval "$(atuin init zsh)"
bindkey -M emacs '^R' atuin-search
bindkey -M viins '^R' atuin-search
```

`ATUIN_NOBIND=true` must be exported **before** `atuin init zsh` runs. It
suppresses Atuin's entire default keymap — including its Up-arrow binding,
which would otherwise displace `zsh-autocomplete`'s history menu. Ctrl+R is
then bound back by hand. See `ZSH-AUTOCOMPLETE.md` §5.2.

---

## 3. Do not install `atuinsh/atuin` as an Antidote plugin

`antidote install atuinsh/atuin` appears to work but is wrong:

- It clones the **full Rust source repository** (~26 MB of crates, Dockerfiles,
  k8s manifests). No binary is built. The only usable file is a three-line
  `atuin.plugin.zsh` that runs `source <(atuin init zsh)`.
- That plugin fires at `antidote load`, i.e. **before** `ATUIN_NOBIND=true` is
  exported further down `~/.zshrc`. Atuin therefore initialises with its default
  keymap and grabs the **Up arrow**, defeating the entire arrangement in §2. The
  later, correctly-configured `atuin init` does not undo that binding.
- It is nondeterministic: `~/.atuin/bin` only joins `$PATH` near the end of
  `~/.zshrc`, so in a clean login shell the plugin's `$+commands[atuin]` guard
  fails and it silently does nothing, while in a nested shell (inherited `PATH`)
  it fires and hijacks the key. Same config, different behaviour per shell.
- It duplicates work that `~/.zshrc` already does.

### Removal

```sh
sed -i '' '/atuinsh\/atuin/d' ~/.zsh_plugins.txt
rm -rf ~/.zsh/plugins/github.com/atuinsh
rm -f ~/.zsh_plugins.zsh          # force Antidote to rebuild its static bundle
exec zsh
```

Verify afterwards — Up must belong to zsh-autocomplete, Ctrl+R to Atuin:

```zsh
grep -c atuin ~/.zsh_plugins.zsh   # expect 0
bindkey '^[[A'                     # expect up-line-or-search
bindkey '^R'                       # expect atuin-search
```

---

## 4. Backfilling history from before the Atuin install

Symptom: the oldest row in Atuin is the install moment itself, and years of
`~/.zsh_history` are invisible to Ctrl+R.

Diagnose it — if the oldest entry is `atuin register`, the import never ran:

```sh
sqlite3 ~/.local/share/atuin/history.db \
  "SELECT datetime(min(timestamp)/1000000000,'unixepoch','localtime'), count(*) FROM history;"
```

A genuine bulk import also shows up as a single session holding thousands of
rows; ordinary sessions hold tens:

```sh
sqlite3 ~/.local/share/atuin/history.db \
  "SELECT count(*) c FROM history GROUP BY session ORDER BY c DESC LIMIT 3;"
```

### 4.1 Why plain `atuin import auto` is the wrong fix afterwards

Reading `crates/atuin-client/src/import/zsh.rs`:

- **No deduplication.** Every line is pushed unconditionally. Re-importing adds
  a second copy of everything Atuin already recorded live.
- **Undated lines get fake recent timestamps.** For history lines without the
  `: <epoch>:<duration>;` prefix, the importer uses `now - counter seconds`,
  incrementing per line. A file of undated commands lands inside a window ending
  *right now*, in reverse order, making every legacy command look like it was
  typed this morning. That wrecks recency ranking and stats — and syncs the mess
  to the server.

Whether your file is dated matters, so check first:

```sh
grep -c -E '^: [0-9]+:[0-9]+;' ~/.zsh_history   # timestamped entries
grep -vc -E '^: [0-9]+:[0-9]+;' ~/.zsh_history  # bare entries
```

zsh only writes timestamps with `EXTENDED_HISTORY` / `SHARE_HISTORY` enabled;
anything recorded before those options were set is undated.

### 4.2 The backfill script

Imports only the commands Atuin is missing, dated plausibly *before* the
install so they never outrank real history. Save as `atuin-backfill.py`:

```python
#!/usr/bin/env python3
"""Build a zsh extended-format histfile containing only the commands that are
missing from the atuin database, timestamped just before the atuin install."""
import datetime
import os
import re
import shutil
import sqlite3
import sys
import tempfile

HIST = os.path.expanduser("~/.zsh_history")
DB = os.path.expanduser("~/.local/share/atuin/history.db")
OUT = "/tmp/atuin_backfill.zsh_history"

WINDOW = 30 * 86400  # spread the backfill over the 30 days before the install
GAP = 3600           # ...but never closer together than an hour


def unmetafy(raw: bytes) -> bytes:
    """Reverse zsh's meta-encoding (0x83 escapes the next byte with ^ 32)."""
    if 0x83 not in raw:
        return raw
    out = bytearray()
    meta = False
    for ch in raw:
        if ch == 0x83:
            meta = True
        elif meta:
            meta = False
            out.append(ch ^ 32)
        else:
            out.append(ch)
    return bytes(out)


def sanitize(cmd: str) -> str:
    """A command ending in '\\' is read back as a line continuation and would
    swallow the following history entry, so drop the dangling marker."""
    cmd = cmd.rstrip()
    while cmd.endswith("\\"):
        cmd = cmd[:-1].rstrip()
    return cmd


def read_entries(path):
    """Yield logical commands, reassembling backslash-continued lines."""
    entries = []
    with open(path, "rb") as fh:
        for raw in fh.read().split(b"\n"):
            try:
                line = unmetafy(raw).decode("utf-8")
            except UnicodeDecodeError:
                continue  # skip lines we cannot decode, as atuin itself does
            if entries and entries[-1].endswith("\\"):
                entries[-1] = entries[-1][:-1] + "\\\n" + line
                continue
            m = re.match(r"^: \d+:\d+;(.*)$", line, re.S)
            entries.append(m.group(1) if m else line)
    return [e for e in (sanitize(x) for x in entries) if e.strip()]


def decode(cmd: str) -> str:
    """Histfile encoding -> real command text. zsh writes an embedded newline as
    backslash+newline; the db stores the decoded text, so only decode this side."""
    return cmd.replace("\\\n", "\n").strip()


def snapshot():
    """Copy the db *with* its WAL, otherwise recent entries look missing."""
    tmp = tempfile.mkdtemp(prefix="atuin-snap-")
    snap = os.path.join(tmp, "history.db")
    for suffix in ("", "-wal", "-shm"):
        if os.path.exists(DB + suffix):
            shutil.copy2(DB + suffix, snap + suffix)
    return tmp, snap


def main():
    zsh_entries = read_entries(HIST)

    tmp, snap = snapshot()
    con = sqlite3.connect(snap)
    in_atuin = {r[0].strip() for r in con.execute("select command from history")}
    install_epoch = con.execute("select min(timestamp) from history").fetchone()[0]
    con.close()
    shutil.rmtree(tmp, ignore_errors=True)

    if install_epoch is None:
        print("empty atuin db — just run 'atuin import auto' instead")
        return 1
    install_epoch //= 1_000_000_000

    missing, seen = [], set()
    for cmd in zsh_entries:
        key = decode(cmd)
        if key in in_atuin or key in seen:
            continue
        seen.add(key)
        missing.append(cmd)

    if not missing:
        print("nothing to import: atuin already has every zsh history command")
        return 1

    step = min(GAP, WINDOW // len(missing)) or 1
    start = install_epoch - 3600 - step * len(missing)

    with open(OUT, "w", encoding="utf-8") as fh:
        for i, cmd in enumerate(missing):
            fh.write(f": {start + i * step}:0;{cmd}\n")

    fmt = "%Y-%m-%d %H:%M:%S"
    first = datetime.datetime.fromtimestamp(start).strftime(fmt)
    last = datetime.datetime.fromtimestamp(start + (len(missing) - 1) * step).strftime(fmt)
    print(f"atuin unique commands:  {len(in_atuin)}")
    print(f"zsh history commands:   {len(zsh_entries)}")
    print(f"missing -> to import:   {len(missing)}")
    print(f"synthetic timestamps:   every {step}s, from {first} to {last}")
    print(f"written to:             {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

### 4.3 Procedure

```sh
# 1. Back up first — the import is not trivially reversible.
BK=~/atuin-backup-$(date +%Y%m%d-%H%M%S); mkdir -p "$BK"
cp ~/.local/share/atuin/history.db*  "$BK"/
cp ~/.zsh_history "$BK"/

# 2. Generate the filtered histfile and read the summary.
python3 atuin-backfill.py

# 3. Sanity check: no entry may end in a dangling backslash.
grep -c '\\$' /tmp/atuin_backfill.zsh_history   # expect 0

# 4. Import only that file.
HISTFILE=/tmp/atuin_backfill.zsh_history atuin import zsh

# 5. Confirm the row count matches, then push to the server.
python3 atuin-backfill.py     # expect "nothing to import"
atuin sync
```

### 4.4 Pitfalls

**Trailing backslashes merge entries.** A command whose text ends in `\` is
re-read as a line continuation and swallows the *following* history entry,
timestamp prefix and all. On this machine 27 such rows absorbed 204 commands on
the first attempt. `sanitize()` in §4.2 exists solely for this. Detect it with:

```sh
sqlite3 ~/.local/share/atuin/history.db \
  "SELECT count(*) FROM history WHERE command GLOB '*: 1[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]:0;*';"
```

Note the **ten** digit classes — an epoch is 10 digits, and a nine-digit glob
silently reports a clean zero.

**`--before` / `--after` parse as UTC**, while Atuin *displays* local time. On
CEST (UTC+2), `--before "2025-06-14 16:00"` also matches 17:59 local. Always
confirm the boundary with a read-only query before deleting.

**`--delete` refuses to run without a search query.** There is no "delete
everything matching this time range" flag short of `--delete-it-all`. Combining
`--before` with a series of broad queries (`e`, `a`, `o`, …) is safe, because
`--before` confines every match to the window being cleaned.

**Query the db through a snapshot that includes the WAL.** Copying only
`history.db` omits everything still in `history.db-wal`, which makes recent
commands look absent and inflates the "missing" count.

**Compare in one direction only.** The db stores decoded command text; the
histfile stores it with backslash-escaped newlines. Decoding *both* sides strips
legitimate shell continuations from db rows and reports phantom differences.

### 4.5 Rollback

Undo a bad backfill without touching genuine post-install history, using a
cutoff *before* the install moment (UTC — see §4.4):

```sh
CUT="2025-06-14 13:00"
for q in e a o i s t n r l u d c m p h g b f k v w y x z j q 0 1 2 3 4 5 6 7 8 9; do
  atuin search --before "$CUT" --delete "$q" >/dev/null 2>&1
done
sqlite3 ~/.local/share/atuin/history.db \
  "SELECT count(*) FROM history WHERE timestamp/1000000000 < <install_epoch>;"   # expect 0
```

Deletions made through `atuin search --delete` propagate to the sync server;
restoring the backup from §4.3 step 1 does not, and discards everything
recorded since the backup.

---

## 5. Verification

```sh
atuin --version
atuin status                     # sync frequency, last sync, server, username
atuin stats                      # total / unique commands
```

In an interactive shell:

```zsh
echo $ATUIN_NOBIND               # true
zle -la | grep -c atuin          # widgets registered
print $precmd_functions          # exactly one _atuin_precmd, no duplicates
bindkey '^R'; bindkey '^[[A'     # atuin-search / up-line-or-search
```

Spot-check that a legacy command really came across — use `full-text`, since the
default fuzzy mode matches loosely and produces confusing hits:

```sh
atuin search --search-mode full-text --format "{time} | {command}" "<old command>"
```

---

## 6. Reference — result on this machine

| | before | after |
|---|---|---|
| Rows in db | 3010 | 3654 |
| Unique commands | 1591 | 2752 |
| Oldest entry | 2025-06-14 (install) | 2025-05-20 |

615 legacy commands were backfilled from 2223 `~/.zsh_history` entries; the rest
were already present from live capture.
