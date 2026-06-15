#!/bin/sh
# Claude Code status line — mirrors Powerlevel10k powerline styling (~/.p10k.zsh).
# Segments: account · dir · git · model · context · rate-limit window (5h/7d + reset).
input=$(cat)

cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty')
model=${model%% *}   # first word only (e.g. "Opus 4.8" -> "Opus")
ctx=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
fh_pct=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
fh_reset=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
sd_pct=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

home="$HOME"
target="${cwd:-$(pwd)}"

# --- Directory (shorten $HOME to ~) ---
dir="${target#"$home"}"
[ "$dir" != "$target" ] && dir="~$dir"

# --- Account badge from logged-in email ---
email=$(jq -r '.oauthAccount.emailAddress // empty' "$home/.claude.json" 2>/dev/null)
domain=${email##*@}
case "$domain" in
  "")          acct="" ;;
  ozeaon.com)  acct="OZ";  acct_bg=96; acct_fg=255 ;;
  *)           acct="MAX"; acct_bg=66; acct_fg=255 ;;
esac

# --- Rate-limit window (subscription usage) ---
# pct -> pastel gradient bg, pale green (0%) through pale yellow to pale red (100%).
# Walks the 256-colour cube: r ramps up 0->50, g ramps down 50->100, b held pastel.
pct_bg() {
  n=${1%.*}; [ "$n" -gt 100 ] && n=100; [ "$n" -lt 0 ] && n=0
  if [ "$n" -le 50 ]; then r=$((3 + (n * 2 + 25) / 50)); g=5; else r=5; g=$((5 - ((n - 50) * 2 + 25) / 50)); fi
  echo "$((16 + 36 * r + 6 * g + 3)) 235"
}
fmt_pct() { printf '%.0f%%' "$1"; }
# Single usage segment, e.g. "81% (3h 45m) 7d:28%"
usage=""
if [ -n "$fh_pct" ]; then
  usage="$(fmt_pct "$fh_pct")"
  if [ -n "$fh_reset" ]; then
    now=$(date +%s)
    diff=$((fh_reset - now))
    if [ "$diff" -gt 0 ]; then
      h=$((diff / 3600)); m=$(((diff % 3600) / 60))
      if [ "$h" -gt 0 ]; then usage="$usage (${h}h ${m}m)"; else usage="$usage (${m}m)"; fi
    fi
  fi
  [ -n "$sd_pct" ] && usage="$usage 7d:$(fmt_pct "$sd_pct")"
fi

# --- Powerline renderer (p10k MODE: powerline arrows) ---
ESC=$(printf '\033')
ARROW=$(printf '\356\202\260')   # U+E0B0
out=""; prev_bg=""
seg() {
  bg=$1; fg=$2; shift 2; text="$*"
  [ -z "$text" ] && return
  if [ -n "$prev_bg" ]; then
    out="${out}${ESC}[38;5;${prev_bg}m${ESC}[48;5;${bg}m${ARROW}"
  fi
  out="${out}${ESC}[48;5;${bg}m${ESC}[38;5;${fg}m ${text} "
  prev_bg=$bg
}

[ -n "$acct" ] && seg "$acct_bg" "$acct_fg" "$acct"
seg 67 255 "$dir"
[ -n "$model" ] && seg 139 255 "$model"
if [ -n "$usage" ]; then
  set -- $(pct_bg "$fh_pct"); seg "$1" "$2" "$usage"
fi
if [ -n "$ctx" ]; then
  set -- $(pct_bg "$ctx"); seg "$1" "$2" "ctx $(fmt_pct "$ctx")"
fi

out="${out}${ESC}[0m"
[ -n "$prev_bg" ] && out="${out}${ESC}[38;5;${prev_bg}m${ARROW}${ESC}[0m"
printf '%s' "$out"
