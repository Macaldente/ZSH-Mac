# ======================
#   .zshrc Configuration
# ======================

# --- OS-Wächter: diese .zshrc ist nur für macOS (Linux-Version: Repo ZSH-Linux)
[[ $OSTYPE == darwin* ]] || { print -P "%F{red}ZSH-Mac/.zshrc ist nur für macOS – Laden abgebrochen (\$OSTYPE=$OSTYPE).%f"; return 1 }

# --- PATH initializer
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"

# Homebrew formulae with custom paths
export PATH="/opt/homebrew/opt/libxml2/bin:$PATH"
export PATH="/opt/homebrew/opt/ffmpeg-full/bin:$PATH"

# --- Plugin manager (Antidote)
ANTIDOTE_DIR="${HOME}/.zsh/antidote"
if [[ ! -d "$ANTIDOTE_DIR" ]]; then
  git clone --depth=1 https://github.com/mattmc3/antidote.git "$ANTIDOTE_DIR"
fi

export ANTIDOTE_HOME="${HOME}/.zsh/plugins"
source "$ANTIDOTE_DIR/antidote.zsh"

ZSH_PLUGINS_FILE="${ZDOTDIR:-$HOME}/.zsh_plugins.txt"
if [[ ! -f "$ZSH_PLUGINS_FILE" ]]; then
  cat > "$ZSH_PLUGINS_FILE" <<'EOF'
marlonrichert/zsh-autocomplete
mafredri/zsh-async
zsh-users/zsh-autosuggestions
Aloxaf/fzf-tab
zsh-users/zsh-syntax-highlighting
EOF
fi

# --- History
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt INC_APPEND_HISTORY SHARE_HISTORY
setopt HIST_VERIFY
setopt HIST_IGNORE_ALL_DUPS

# "#" leitet auch bei direkt eingetippten Befehlen einen Kommentar ein
setopt INTERACTIVE_COMMENTS

# --- Completion cache
# NOTE: zsh-autocomplete runs compinit itself and stubs it out afterwards.
# Upstream requires that we do NOT call compinit here. It honours $ZSH_COMPDUMP.
export ZSH_COMPDUMP="${ZDOTDIR:-$HOME}/.cache/zsh/zcompdump"
mkdir -p "${ZDOTDIR:-$HOME}/.cache/zsh"

# --- Plugin loader
ZSH_AUTOSUGGEST_STRATEGY=( history )
ZSH_HIGHLIGHT_HIGHLIGHTERS=( main brackets )
antidote load "$ZSH_PLUGINS_FILE"

# --- Tool initialization
eval "$(zoxide init zsh)"
eval "$(starship init zsh)"

# FZF configuration file
# Keep Ctrl+T (files) and Alt+C (dirs). Ctrl+R is owned by atuin further below.
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
if command -v fzf >/dev/null 2>&1; then
  eval "$(fzf --zsh)" 2>/dev/null || true
  # fzf's shell integration steals Tab for `fzf-completion`; hand it back to fzf-tab.
  if (( $+widgets[fzf-tab-complete] )); then
    bindkey -M emacs '^I' fzf-tab-complete
    bindkey -M viins '^I' fzf-tab-complete
  fi
fi

# --- Alias section
# ls
alias ls='eza --group-directories-first --icons=always'
alias ll='eza -l'
alias la='eza -a --group-directories-first --icons=always'
alias lla='eza -la'
# eza
alias eza='eza -a --group-directories-first --icons=always'
alias ezal='eza -l'
alias ezaa='eza -a --group-directories-first --icons=always'
alias ezla='eza -la'

# -------------
# own functions
# -------------

# clear the clipboard
clrclp () {
    pbcopy < /dev/null
}

# generate password: default 16 digits, optional less/more digits:
genpass() {
    jot -r -c ${1:-16} 33 126 | tr -d '\n' | pbcopy && echo "Neues Passwort (${1:-16} Zeichen) in der Zwischenablage verfügbar"
}

# scan the download directory
vscand () {
    clamdscan --fdpass --multiscan --no-summary ~/Downloads
}

# scan a path by clamdscan
vscan() {
  if [ -z "$1" ]; then
    echo "Bitte gib einen Pfad an, z. B.: vscan ~/Downloads"
    return 1
  fi

  if [ ! -e "$1" ]; then
    echo "Pfad '$1' existiert nicht."
    return 1
  fi

  clamdscan --fdpass --multiscan --no-summary "$1"
}

# youtube downloader mp4
ytv() {
    yt-dlp -t mp4 "$@"
}

# neuer Blogpost in einem Zola-Repo unter ~/Git (reading, join-linux, …)
#   newpost <repo> "Titel"   z. B. newpost join-linux "Fedora 45 ist da"
#   newpost "Titel"          wenn man schon im Repo steht
# Legt content/blog/<slug>.md als Entwurf an, startet `zola serve --drafts`
# im Hintergrund (Browser öffnet sich), öffnet $EDITOR und beendet den
# Server, sobald der Editor geschlossen wird.
newpost() {
  emulate -L zsh
  setopt extended_glob
  local base=~/Git repo top
  local -a repos=($base/*/content/blog(N/:h:h:t))

  if [[ -n $1 && -d $base/$1/content/blog ]]; then
    repo=$base/$1; shift
  elif top=$(git rev-parse --show-toplevel 2>/dev/null) && [[ -d $top/content/blog ]]; then
    repo=$top
  else
    print -u2 "Aufruf: newpost <repo> \"Titel\"  (Repos: ${(j:, :)repos})"
    return 1
  fi

  local title=$*
  [[ -z $title ]] && { print -u2 "Bitte einen Titel angeben."; return 1 }

  # Titel -> URL-Slug: klein, Umlaute umschreiben, alles andere zu "-"
  local slug=${(L)title}
  slug=${slug//ä/ae}; slug=${slug//ö/oe}; slug=${slug//ü/ue}; slug=${slug//ß/ss}
  slug=${slug//[^a-z0-9]##/-}
  slug=${${slug#-}%-}

  local qtitle=${title//\"/\\\"}   # " im Titel für TOML maskieren
  local file=$repo/content/blog/$slug.md
  if [[ -e $file ]]; then
    print -u2 "Gibt es schon: $file"
    return 1
  fi

  cat > $file <<EOF
+++
title = "$qtitle"
date = $(print -P '%D{%Y-%m-%d}')
description = ""
draft = true
[taxonomies]
tags = []
+++

EOF

  cd $repo || return 1
  print -P "%F{green}Angelegt:%f content/blog/$slug.md"

  local pid log=${TMPDIR:-/tmp}/newpost-zola.log
  zola serve --drafts --open &>$log &!
  pid=$!
  sleep 1
  if ! kill -0 $pid 2>/dev/null; then
    print -P "%F{red}zola serve ist abgebrochen%f (Vorschau fehlt, Datei ist trotzdem angelegt):"
    grep -m3 -i error $log
    read -sk1 '?Weiter mit beliebiger Taste …'; print
  fi
  ${=EDITOR:-nano} $file
  kill $pid 2>/dev/null

  print -P "Veröffentlichen: %F{yellow}draft = false%f setzen, dann"
  print    "  git add content/blog/$slug.md && git commit -m \"Neuer Post '$title'\" && git push"
}

# Tab-Vervollständigung: erstes Argument = Zola-Repo unter ~/Git
_newpost() {
  (( CURRENT == 2 )) || return 1
  local -a repos=(~/Git/*/content/blog(N/:h:h:t))
  _describe 'Repo' repos
}
compdef _newpost newpost

# --- Nearly finished
# Atuin: bind keys manually so they are set after zsh-autocomplete.
# Ctrl+R and the Up arrow both open atuin instead of the zsh history.
# ~/.atuin/bin/env only exists when atuin was installed via the official
# install script rather than Homebrew; guard it so Homebrew-only installs
# don't error on every shell start.
[ -f "$HOME/.atuin/bin/env" ] && . "$HOME/.atuin/bin/env"
export ATUIN_NOBIND=true
eval "$(atuin init zsh)"
bindkey -M emacs '^R' atuin-search
bindkey -M viins '^R' atuin-search
bindkey -M emacs '^[[A' atuin-up-search
bindkey -M viins '^[[A' atuin-up-search
bindkey -M emacs '^[OA' atuin-up-search
bindkey -M viins '^[OA' atuin-up-search

# --- PATH finish
if [[ -d /usr/local/bin/podman ]]; then
  export PATH="$PATH:/usr/local/bin/podman"
fi

export PATH="$HOME/.local/bin:$PATH"

# Locale settings
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Load local secrets (API keys, etc.)
[ -f ~/.secrets ] && source ~/.secrets
# --- End of .zshrc ++++++++

# rmpc startet/beendet mpd automatisch (siehe ~/.local/bin/music)
alias rmpc='music'
