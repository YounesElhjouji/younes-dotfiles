#!/bin/bash
# Claude Code status line, one row, solarized accents:
#   ◆ Fable 5.1 · medium  │  ⎇ main 3 files +120 −34  │  ctx ◑ 41%  │  weekly ▰▰▰▱▱▱▱▱ 32%  ↻ 6d 22h  │  my-project
# Reads session JSON on stdin (schema: https://code.claude.com/docs/en/statusline).

input=$(cat)
# a UTF-8 locale for the glyphs: en_US on macOS, C.UTF-8 on Linux boxes without en_US generated
UTF=en_US.UTF-8; [ "$(uname)" = Darwin ] || UTF=C.UTF-8
export LC_ALL=${LC_ALL:-$UTF} LANG=${LANG:-$UTF}

hex() { printf '\033[38;2;%d;%d;%dm' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"; }
B=$'\033[1m'; R=$'\033[0m'
# Light or dark: explicit override, then macOS appearance, then the terminal's own answer via tmux
# (tmux >= 3.6 asks Ghostty & co., so a remote VM session follows the laptop), else dark.
THEME=${CLAUDE_STATUSLINE_THEME:-}
if [ -z "$THEME" ] && [ "$(uname)" = Darwin ]; then
  [ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" = "Dark" ] && THEME=dark || THEME=light
fi
if [ -z "$THEME" ] && [ -n "$TMUX" ]; then
  # clients attached to this pane's session (a plain `display -p` has no client outside a key binding)
  SESS=$(tmux display -p ${TMUX_PANE:+-t "$TMUX_PANE"} '#{session_name}' 2>/dev/null)
  case "$(tmux list-clients ${SESS:+-t "$SESS"} -F '#{client_theme}' 2>/dev/null | grep -m1 -E 'light|dark')" in
    light) THEME=light ;; dark) THEME=dark ;;
  esac
fi
THEME=${THEME:-dark}

# Solarized tones by role, flipped for light mode.
# Everything but the percentages is pulled toward the background so the line stays quiet:
#   HI percentages · MID model, bar fill · LO labels and secondary text · RULE separators
# Accents are blended ~50-60% into the background.
if [ "$THEME" = light ]; then
  # light backgrounds need more contrast for the same visual weight, so these sit ~1.5x higher
  HI=$(hex '#49626a'); MID=$(hex '#6f8184'); LO=$(hex '#95a09d'); RULE=$(hex '#ced0c4')
  VIOLET=$(hex '#8789ca'); CYAN=$(hex '#279992'); ADDC=$(hex '#8b9d0b'); DELC=$(hex '#e77168')
else
  HI=$(hex '#839496'); MID=$(hex '#586e75'); LO=$(hex '#35535c'); RULE=$(hex '#1a3f49')
  VIOLET=$(hex '#41558b'); CYAN=$(hex '#197271'); ADDC=$(hex '#42621b'); DELC=$(hex '#6e2e32')
fi
YELLOW=$(hex '#b58900'); ORANGE=$(hex '#cb4b16'); RED=$(hex '#dc322f')   # warnings stay full strength
SEP="${RULE}  │  ${R}"
CELLS=8

meter() {  # percent color -> "▰▰▰▰▱▱▱▱", filled in color, rest LO
  local p=${1:-0} col=$2 n out=""
  [ "$p" -gt 100 ] && p=100
  n=$(( (p * CELLS + 50) / 100 ))
  for ((i=0;i<n;i++));     do out="${out}▰"; done
  out="${col}${out}${R}${LO}"
  for ((i=n;i<CELLS;i++)); do out="${out}▱"; done
  printf '%s%s' "$out" "$R"
}

short() {  # 103324 -> "103k", 1500 -> "1.5k", 42 -> "42"
  local n=$1
  if   [ "$n" -ge 10000 ]; then printf '%dk' $(( n / 1000 ))
  elif [ "$n" -ge 1000 ];  then printf '%d.%dk' $(( n / 1000 )) $(( n % 1000 / 100 ))
  else                          printf '%d' "$n"; fi
}

countdown() {  # epoch seconds -> "6d 22h" / "3h 12m" / "45m"
  local diff=$(( $1 - $(date +%s) ))
  [ "$diff" -le 0 ] && { printf 'now'; return; }
  local d=$(( diff / 86400 )) h=$(( (diff % 86400) / 3600 )) m=$(( (diff % 3600) / 60 ))
  if   [ "$d" -gt 0 ]; then printf '%dd %dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%dh %dm' "$h" "$m"
  else                      printf '%dm' "$m"; fi
}

MODEL=$(jq -r '.model.display_name // "?"' <<<"$input")
EFFORT=$(jq -r '.effort.level // empty' <<<"$input")
PCT=$(jq -r '.context_window.used_percentage // 0' <<<"$input" | cut -d. -f1)
CWD=$(jq -r '.workspace.current_dir // .cwd // "."' <<<"$input")
SEVEN=$(jq -r '.rate_limits.seven_day.used_percentage // empty' <<<"$input" | cut -d. -f1)
SEVEN_AT=$(jq -r '.rate_limits.seven_day.resets_at // empty' <<<"$input")
BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)

# Per-model weekly limit (e.g. "Current week (Fable)" in /usage). The session JSON only has the
# all-models window, so read /api/oauth/usage, cached and refreshed in the background every 60s.
USAGE_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline/usage.json"
fetch_usage() {  # write the cache atomically; keep the old one on any failure
  local tok tmp="$USAGE_CACHE.$$"
  tok=$( { security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null ||
           cat "$HOME/.claude/.credentials.json" 2>/dev/null; } | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
  [ -n "$tok" ] || return
  curl -sf -m 10 https://api.anthropic.com/api/oauth/usage \
    -H "Authorization: Bearer $tok" -H "anthropic-beta: oauth-2025-04-20" > "$tmp" &&
    jq -e '.limits' "$tmp" >/dev/null 2>&1 && mv "$tmp" "$USAGE_CACHE"
  rm -f "$tmp"
}
mkdir -p "${USAGE_CACHE%/*}"
STAMP="$USAGE_CACHE.stamp"   # touched before each fetch so concurrent redraws don't all fetch
if [ ! -f "$STAMP" ] || [ $(( $(date +%s) - $(date -r "$STAMP" +%s) )) -ge 60 ]; then
  touch "$STAMP"
  ( fetch_usage ) </dev/null >/dev/null 2>&1 &
fi
WEEK_LABEL="weekly"
if [ -f "$USAGE_CACHE" ]; then
  # scoped weekly limit whose model name prefixes the selected model ("Fable" ~ "Fable 5.1")
  read -r SCOPED_PCT SCOPED_AT SCOPED_NAME < <(jq -r --arg m "$MODEL" '
    [.limits[]? | select(.kind == "weekly_scoped" and .scope.model.display_name != null)
      | (.scope.model.display_name | ascii_downcase) as $n | select($m | ascii_downcase | startswith($n))][0]
    | select(. != null)
    | "\(.percent) \(.resets_at | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) \(.scope.model.display_name)"
  ' "$USAGE_CACHE" 2>/dev/null)
  if [ -n "$SCOPED_PCT" ]; then
    SEVEN=${SCOPED_PCT%.*}; SEVEN_AT=$SCOPED_AT; WEEK_LABEL="${SCOPED_NAME} weekly"
  fi
fi

# model · effort
SEG_MODEL="${VIOLET}◆${R} ${MID}${MODEL}${R}"

level_color() {  # percent -> HI, orange from 80%, bold red from 95% (context and weekly)
  if   [ "$1" -ge 95 ]; then printf '%s' "${B}${RED}"
  elif [ "$1" -ge 80 ]; then printf '%s' "$ORANGE"
  else                       printf '%s' "$HI"; fi
}
if [ -n "$EFFORT" ]; then
  case "$EFFORT" in
    xhigh|max) EC=$ORANGE ;;
    high)      EC=$YELLOW ;;
    *)         EC=$LO ;;
  esac
  SEG_MODEL="${SEG_MODEL}${LO} · ${R}${EC}${EFFORT}${R}"
fi

# branch
SEG_GIT=""
if [ -n "$BRANCH" ]; then
  # "3 files +120 −34": changed files (incl. untracked) and line totals vs HEAD
  FILES=$(git -C "$CWD" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  DIRTY=""
  if [ "$FILES" -gt 0 ]; then
    read -r ADD DEL < <(git -C "$CWD" diff HEAD --numstat 2>/dev/null |
      awk '$1 != "-" {a+=$1; d+=$2} END {print a+0, d+0}')
    [ "$FILES" -eq 1 ] && NOUN=file || NOUN=files
    DIRTY=" ${LO}${FILES} ${NOUN}${R}"
    [ "$ADD" -gt 0 ] && DIRTY="${DIRTY} ${ADDC}+$(short "$ADD")${R}"
    [ "$DEL" -gt 0 ] && DIRTY="${DIRTY} ${DELC}−$(short "$DEL")${R}"
  fi
  SEG_GIT="${CYAN}⎇ ${BRANCH}${R}${DIRTY}"
fi

# context: "ctx ◑ 41%"
[ "$PCT" -gt 100 ] 2>/dev/null && PCT=100
NC=$(level_color "$PCT"); IC=$NC; [ "$PCT" -lt 80 ] && IC=$MID   # icon a step below the number
# fill icon, nearest quarter: ○ ◔ ◑ ◕ ●
if   [ "$PCT" -lt 13 ]; then ICON="○"
elif [ "$PCT" -lt 38 ]; then ICON="◔"
elif [ "$PCT" -lt 63 ]; then ICON="◑"
elif [ "$PCT" -lt 88 ]; then ICON="◕"
else                         ICON="●"; fi
SEG_CTX="${LO}ctx ${R}${IC}${ICON}${R} ${NC}${PCT}%${R}"

# weekly meter
SEG_WEEK=""
if [ -n "$SEVEN" ]; then
  WC=$(level_color "$SEVEN")
  SEG_WEEK="${LO}${WEEK_LABEL} ${R}$(meter "$SEVEN" "$WC") ${WC}${SEVEN}%${R}"
  RC=$LO; [ "$SEVEN" -ge 80 ] && RC=$WC   # countdown takes the warning color once it matters
  [ -n "$SEVEN_AT" ] && SEG_WEEK="${SEG_WEEK}  ${RC}↻ $(countdown "$SEVEN_AT")${R}"
fi

LINE="${SEG_MODEL}"
[ -n "$SEG_GIT" ]  && LINE="${LINE}${SEP}${SEG_GIT}"
LINE="${LINE}${SEP}${SEG_CTX}"
[ -n "$SEG_WEEK" ] && LINE="${LINE}${SEP}${SEG_WEEK}"
LINE="${LINE}${SEP}${LO}${CWD##*/}${R}"   # directory name, last and faint
printf '%s\n\342\200\213' "$LINE"
