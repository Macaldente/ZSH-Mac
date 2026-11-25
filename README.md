# ZSH-Mac

MacOS dotfiles und Konfigurationsdateien für ZSH, SSH und weitere Tools.

---

## Inhalt

Das Repo bildet das Home-Verzeichnis ab: Jede Datei liegt unter demselben
relativen Pfad wie ihr Ziel in `~` und wird per `stow` dorthin verlinkt.

| Datei im Repo | Beschreibung |
|---|---|
| `.zshrc` | ZSH-Konfiguration (Antidote-basiert) |
| `.zsh_plugins.txt` | Antidote Plugin-Liste |
| `.config/starship.toml` | Starship Prompt-Konfiguration |
| `.config/atuin/config.toml` | Atuin-Konfiguration |
| `.config/ghostty/config` | Ghostty-Konfiguration |
| `.homebrew/brew.env` | Homebrew-Umgebungsvariablen |
| `.vimrc` | Vim-Konfiguration |
| `.nanorc` | Nano-Konfiguration |
| `.stowrc` | Standard-Optionen für `stow` (Repo-Pfad, Ziel `~`, `--no-folding`) |
| `.stow-local-ignore` | Dateien, die `stow` nicht verlinkt (Doku, Git, generierte Dateien) |
| `ZSH-AUTOCOMPLETE.md` | Ladereihenfolge, `compinit`-Regel und Tastenbelegung (Tab / ↑ / Ctrl+R) |
| `ATUIN.md` | Atuin-Setup, Antidote-Fallstrick und Nachimport der Alt-History |

`.zsh_plugins.zsh` liegt bewusst **nicht** im Repo: Antidote erzeugt die Datei
selbst und ersetzt sie beim Neubau per `mv -f` — ein Symlink würde dabei wieder
zur normalen Datei.

---

## Installation

> **Nur auf macOS verwenden.** Die Linux-Variante liegt in
> [`ZSH-Linux`](https://github.com/Macaldente/ZSH-Linux), deren
> Installationsschritte (`cp .zshrc .zsh_plugins.txt ~/`) auf dem Mac **nicht**
> ausführen: Weil `~/.zshrc` hier ein `stow`-Symlink ist, würde `cp` den
> Linux-Inhalt direkt in dieses Repo schreiben. Beide `.zshrc` haben deshalb
> ganz oben einen OS-Wächter, der das Laden auf dem falschen System mit einer
> Meldung abbricht. Wiederherstellen mit `git restore .zshrc .zsh_plugins.txt`.

### Voraussetzungen

Initiale CLI-Tools installieren:
```zsh
brew install antidote atuin eza fzf genpass helix starship zoxide
```

> **Atuin:** Direkt nach der Installation `atuin import auto` ausführen — ein
> späterer Nachimport ist aufwendig und mit `atuin import auto` allein nicht
> mehr sauber möglich, siehe [`ATUIN.md`](ATUIN.md).
> Atuin **nicht** als Antidote-Plugin installieren (`atuinsh/atuin`) — Begründung
> ebenfalls in [`ATUIN.md`](ATUIN.md).

Weitere CLI-Tools:
```zsh
brew install bat fastfetch podman podman-compose ripgrep rsync stow tree wget
```

Casks:
```zsh
brew install --cask ghostty ungoogled-chromium raycast soundanchor timemachineeditor warp zed
```

### Dotfiles einrichten

Dateien mit `stow` ins Home-Verzeichnis symlinken — im Repo-Ordner:
```zsh
cd ~/Git/ZSH-Mac
stow .
```

Die Optionen kommen aus `.stowrc` (`--dir=~/Git/ZSH-mac`, `--target=~`,
`--no-folding`). `stow` liest die Datei beim ersten Lauf aus dem aktuellen
Ordner und verlinkt sie dabei selbst nach `~/.stowrc` — danach funktioniert
`stow .` aus jedem Ordner. Liegt das Repo woanders, `--dir` in `.stowrc`
anpassen.

`--no-folding` verlinkt nur einzelne Dateien, nie ganze Ordner. So landen
Dateien, die Programme selbst in `~/.config/atuin` oder `~/.config/ghostty`
anlegen, nicht versehentlich im Repo.

Bereits vorhandene Dateien blockieren `stow` („cannot stow … over existing
target“). Diese vorher sichern und aus dem Weg räumen, dann erneut ausführen.
Mit `stow -n -v …` lässt sich vorab prüfen, was passieren würde.

Weil die Dateien in `~` nur Symlinks sind, landet jede Änderung direkt im Repo
und taucht in `git status` auf.

---

## ZSH-Konfiguration

Kernstück ist [`zsh-autocomplete`](https://github.com/marlonrichert/zsh-autocomplete):
das Completion-Menü erscheint **live beim Tippen**, ohne Tastendruck.
Der Aufwand liegt weniger in der Installation als darin, anderen Tools die
benötigten Tasten wieder abzunehmen.

### Ladereihenfolge

Die Reihenfolge in `.zsh_plugins.txt` ist funktionsrelevant:

1. `marlonrichert/zsh-autocomplete` — muss **vor jedem `compdef`** geladen werden
2. `mafredri/zsh-async` — Abhängigkeit, vor den Nutzern
3. `zsh-users/zsh-autosuggestions`
4. `Aloxaf/fzf-tab` — übernimmt beim Laden die aktuelle Tab-Belegung
5. `zsh-users/zsh-syntax-highlighting` — muss **zuletzt** stehen

### compinit

`zsh-autocomplete` ruft `compinit` selbst auf und ersetzt die Funktion danach.
In `.zshrc` steht deshalb **kein eigener `compinit`-Aufruf**, nur der Dump-Pfad:

```zsh
export ZSH_COMPDUMP="${ZDOTDIR:-$HOME}/.cache/zsh/zcompdump"
```

`ZSH_COMPDUMP` ist die Variable, die das Plugin ausliest — ein eigener Name wie
`ZCOMPDUMP` wird stillschweigend ignoriert.

### Tastenbelegung

| Taste | Zuständig | Widget |
|---|---|---|
| *(Tippen)* | zsh-autocomplete Live-Menü | — |
| <kbd>Tab</kbd> | fzf-tab | `fzf-tab-complete` |
| <kbd>↑</kbd> | atuin (Filter `host`) | `atuin-up-search` |
| <kbd>↓</kbd> | zsh-autocomplete | `down-line-or-select` |
| <kbd>Ctrl</kbd>+<kbd>R</kbd> | atuin | `_atuin_search` |
| <kbd>Ctrl</kbd>+<kbd>T</kbd> / <kbd>Alt</kbd>+<kbd>C</kbd> | fzf | `fzf-file-widget` / `fzf-cd-widget` |

Zwei Konflikte werden in `.zshrc` aufgelöst:

- `eval "$(fzf --zsh)"` läuft **nach** `antidote load` und belegt <kbd>Tab</kbd> mit
  `fzf-completion`. Die Belegung wird danach an `fzf-tab` zurückgegeben.
- `atuin init zsh` belegt standardmäßig <kbd>↑</kbd> **und** <kbd>Ctrl</kbd>+<kbd>R</kbd>.
  `ATUIN_NOBIND=true` deaktiviert das Keymap; <kbd>Ctrl</kbd>+<kbd>R</kbd> und <kbd>↑</kbd>
  werden danach manuell gesetzt und überschreiben so das History-Menü von zsh-autocomplete.

> **Merkregel:** Jedes Tool, das `bindkey` ausführt (fzf, atuin, mcfly, navi),
> kollidiert mit zsh-autocomplete, wenn es nach `antidote load` initialisiert.

### Prüfen

`whence autocomplete` ist **kein** gültiger Test — das Plugin definiert keinen
Befehl dieses Namens und der Test schlägt auch bei korrekter Installation fehl.

Die folgenden Zeilen **am Prompt eintippen**, nicht per `zsh -c` ausführen:
`zsh -c` zeichnet keinen Prompt, dadurch läuft der `precmd`-Hook nie und
`compinit` bleibt aus — `${#_comps}` meldet dann fälschlich `0`.

```zsh
(( $+functions[.autocomplete__main] )) && print geladen
print ${#_comps}                                  # erwartet: einige Tausend, nicht 0
for k in '^I' '^[[A' '^R'; do bindkey "$k"; done  # einzeln abfragen
```

Schnelltest: neue Shell öffnen und `ls --` tippen — das Menü muss von selbst
erscheinen. Details siehe [`ZSH-AUTOCOMPLETE.md`](ZSH-AUTOCOMPLETE.md).

---

## SSH-Konfiguration

Die `~/.ssh/config` enthält Host-Aliase für alle Remote-Systeme.

### Globale Einstellung (Locale-Fix)

macOS sendet standardmäßig alle `LANG`/`LC_*` Variablen an Remote-Hosts.
Dies wird in `~/.ssh/config` global unterdrückt:

```ssh-config
Host *
    SendEnv -LANG -LC_*
```

---

## Changelog

- **2026-11-25** — OS-Wächter am Anfang der `.zshrc`: auf einem Nicht-macOS-System
  bricht das Laden mit einer Meldung ab (Gegenstück in `ZSH-Linux`). Hinweis in
  der Installation, die Linux-Schritte nicht auf dem Mac auszuführen.

- **2026-11-15** — `.stowrc` ergänzt: `stow .` genügt, die Optionen müssen nicht
  mehr von Hand angegeben werden.
- **2026-11-15** — Auf `stow`-Symlinks umgestellt. Die Dateien liegen jetzt unter
  ihren echten Pfaden (`.config/…`, `.homebrew/brew.env`), `.stow-local-ignore`
  hält Doku und Git-Dateien aus `~` heraus. `.zsh_plugins.zsh` aus dem Repo
  entfernt (generiert, verträgt keinen Symlink). Starship zeigt `meister` jetzt als
  festen Text statt über einen Benutzernamen-Alias, damit kein Benutzername im
  Repo steht.
- **2026-11-15** — <kbd>↑</kbd> öffnet jetzt Atuin (`atuin-up-search`) statt des
  History-Menüs von zsh-autocomplete. Für die Pfeiltaste filtert Atuin auf `host`
  (alle Befehle dieses Macs), <kbd>Ctrl</kbd>+<kbd>R</kbd> sucht weiterhin global.
  Atuin-Konfiguration als `atuin.toml` ins Repo aufgenommen, versehentlich
  eingecheckte Terminal-Ausgabe `ghostty` entfernt, `config` und `starship.toml`
  mit dem aktiven Stand abgeglichen.
- **2026-09-06** — [`ATUIN.md`](ATUIN.md) ergänzt: Atuin-Setup, warum `atuinsh/atuin`
  kein Antidote-Plugin sein darf (klont 26 MB Rust-Quellcode und initialisiert Atuin
  vor `ATUIN_NOBIND`, wodurch die <kbd>↑</kbd>-Taste an Atuin fällt), sowie das
  Verfahren für einen nachträglichen History-Import. Ein spätes `atuin import auto`
  dupliziert vorhandene Einträge und datiert undatierte Zeilen auf *jetzt* —
  dokumentiert ist deshalb ein gefilterter Backfill.
- **2026-08-16** — Repository von `ZSH-mac` in `ZSH-Mac` umbenannt (Konsistenz mit `ZSH-Linux`).
- **2026-08-16** — `~/.atuin/bin/env`-Sourcing in `.zshrc` mit einer Existenzprüfung
  abgesichert (`[ -f "$HOME/.atuin/bin/env" ] && . "$HOME/.atuin/bin/env"`).
  Diese Datei wird nur vom offiziellen Atuin-Install-Skript angelegt, nicht von
  Homebrew — die hier dokumentierte Installationsmethode (`brew install ... atuin`)
  erzeugt sie also nicht, wodurch die Zeile bei jedem Shell-Start einen Fehler
  auslöste. Der Fix wurde zuerst in `ZSH-Linux` gefunden und dort interaktiv
  verifiziert, dann hierher zurückportiert.
