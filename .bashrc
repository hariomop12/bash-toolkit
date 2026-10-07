# ~/.bashrc — Hariom's shell config
# https://github.com/hariomop12/bash-toolkit
#
# Layout:
#   1. PATH            — set BEFORE the interactive guard so scripts
#                        that inherit this env also find ~/bin.
#   2. interactive     — everything below needs a TTY.
#   3. my shortcuts    — aliases + ~/bin scripts (play, laptop-health).
#
# Install:  ./install.sh   (symlinks this file to ~/.bashrc)

# ─── 1. PATH (runs for interactive AND non-interactive) ──────
# $HOME is used instead of /home/<user> so this file is portable
# across machines and does not leak a username into the repo.
[ -d "$HOME/bin" ] && export PATH="$HOME/bin:$PATH"
[ -d "$HOME/.opencode/bin" ] && export PATH="$HOME/.opencode/bin:$PATH"

# Non-interactive shell? to kuch mat karo.
case $- in
    *i*) ;;
      *) return;;
esac

# ─── History ─────────────────────────────────────────────────
HISTCONTROL=ignoreboth
shopt -s histappend
HISTSIZE=1000
HISTFILESIZE=2000

shopt -s checkwinsize

# less ko non-text files ke liye friendly banao
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# chroot marker (prompt me dikhta hai)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# Prompt (colour sirf 256-color terminals pe)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt

# xterm ka title bar
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
esac

# Colors
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# ───────────── mere shortcuts ────────────────────────────────
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias c='clear'
alias y='yazi'

# play <gaane ka naam>  →  YouTube se chalao.
# Logic bin/play me hai, aur $HOME/bin PATH me hai to seedha chalta
# hai — alias ki zaroorat nahi. Gaana khatam hone pe agla automatically
# bajta hai (YouTube "up next" feed jaisa).
#
# Deps: sudo apt install yt-dlp mpv

# ── laptop health check ──────────────────────────────────────
# Report: ~/.local/state/noc-monitor.log is NOT part of this repo.
alias health='laptop-health.sh'
alias healthbrief='laptop-health.sh --brief'

# ───────────── yahan se bash ka default ──────────────────────

# aliases alag file me rakhne ho to
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# Tab completion
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
