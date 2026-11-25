# ======================
#   .zshrc Configuration
# ======================

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

# git look: zeigt, ob es Updates vom Remote gibt (Dry-Run für git pull)
#   im Repo   -> prüft nur dieses Repo
#   außerhalb -> prüft alle Repos in ~/Git
git() {
  if [[ "$1" == "look" ]]; then
    local repos r n
    if command git rev-parse --is-inside-work-tree &>/dev/null; then
      repos=("$(command git rev-parse --show-toplevel)")
    else
      repos=(~/Git/*/.git(N:h))
    fi
    for r in $repos; do
      command git -C "$r" fetch -q 2>/dev/null
      n=$(command git -C "$r" rev-list --count HEAD..@{u} 2>/dev/null)
      if [[ -z "$n" ]]; then
        print -P "%F{yellow}${r:t}%f: kein Upstream"
      elif (( n > 0 )); then
        print -P "%F{red}${r:t}%f: $n neue Commits"
        command git -C "$r" log --oneline HEAD..@{u} | sed 's/^/    /'
      else
        print -P "%F{green}${r:t}%f: aktuell"
      fi
    done
  else
    command git "$@"
  fi
}

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
