#!/bin/bash
# Claude Code status line, one row, solarized accents:
#   ◆ Fable 5.1 · medium  │  ⎇ main 3 files +120 −34  │  ctx ◑ 41%  │  weekly ▰▰▰▱▱▱▱▱ 32%  ↻ 6d 22h  │  my-project
# Reads session JSON on stdin (schema: https://code.claude.com/docs/en/statusline).

input=$(cat)
export LC_ALL=${LC_ALL:-en_US.UTF-8} LANG=${LANG:-en_US.UTF-8}

fg() { printf '\033[38;5;%sm' "$1"; }
B=$'\033[1m'; R=$'\033[0m'
# solarized 256-color approximations (work on both dark and light backgrounds)
DIM=$'\033[2m'    # faint: fades toward the background in light and dark themes
TXT=$(fg 245)      # base1
VIOLET=$(fg 61); BLUE=$(fg 33); CYAN=$(fg 37); MAGENTA=$(fg 125); GREEN=$(fg 64); YELLOW=$(fg 136); ORANGE=$(fg 166); RED=$(fg 160)
SEP="${DIM}  │  ${R}"
CELLS=8

meter() {  # percent color -> "▰▰▰▰▱▱▱▱", filled in color, rest faint
  local p=${1:-0} col=$2 n out=""
  [ "$p" -gt 100 ] && p=100
  n=$(( (p * CELLS + 50) / 100 ))
  for ((i=0;i<n;i++));     do out="${out}▰"; done
  out="${col}${out}${R}${DIM}"
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
# "◆ Opus": violet diamond, name in soft white (dark mode) or default foreground (light / Linux)
MC=$'\033[39m'
[ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" = "Dark" ] && MC=$(fg 252)
SEG_MODEL="${VIOLET}◆${R} ${MC}${MODEL}${R}"
if [ -n "$EFFORT" ]; then
  case "$EFFORT" in
    xhigh|max) EC=$ORANGE ;;
    high)      EC=$YELLOW ;;
    *)         EC=$DIM ;;
  esac
  SEG_MODEL="${SEG_MODEL}${DIM} · ${R}${EC}${EFFORT}${R}"
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
    DIRTY=" ${DIM}${FILES} ${NOUN}${R}"
    [ "$ADD" -gt 0 ] && DIRTY="${DIRTY} ${DIM}${GREEN}+$(short "$ADD")${R}"
    [ "$DEL" -gt 0 ] && DIRTY="${DIRTY} ${DIM}${RED}−$(short "$DEL")${R}"
  fi
  SEG_GIT="${CYAN}⎇ ${BRANCH}${R}${DIRTY}"
fi

# context: "ctx ◑ 41%"
[ "$PCT" -gt 100 ] 2>/dev/null && PCT=100
# icon gains weight as context fills: faint, grey, yellow, orange, bold red
IC=$DIM; NC=$TXT
[ "$PCT" -ge 25 ] && IC=$TXT
[ "$PCT" -ge 50 ] && { IC=$YELLOW;         NC=$YELLOW; }
[ "$PCT" -ge 70 ] && { IC="${B}${ORANGE}"; NC=$ORANGE; }
[ "$PCT" -ge 85 ] && { IC="${B}${RED}";    NC="${B}${RED}"; }
# fill icon, nearest quarter: ○ ◔ ◑ ◕ ●
if   [ "$PCT" -lt 13 ]; then ICON="○"
elif [ "$PCT" -lt 38 ]; then ICON="◔"
elif [ "$PCT" -lt 63 ]; then ICON="◑"
elif [ "$PCT" -lt 88 ]; then ICON="◕"
else                         ICON="●"; fi
SEG_CTX="${DIM}ctx ${R}${IC}${ICON}${R} ${NC}${PCT}%${R}"

# weekly meter: green, yellow from 50%, orange from 75%, red from 90%
SEG_WEEK=""
if [ -n "$SEVEN" ]; then
  WC=$GREEN
  [ "$SEVEN" -ge 50 ] && WC=$YELLOW
  [ "$SEVEN" -ge 75 ] && WC=$ORANGE
  [ "$SEVEN" -ge 90 ] && WC=$RED
  WB=""; [ "$SEVEN" -ge 90 ] && WB=$B   # bold only when nearly out
  SEG_WEEK="${DIM}${WEEK_LABEL} ${R}$(meter "$SEVEN" "$WC") ${WB}${WC}$(printf '%2d' "$SEVEN")%${R}"
  RC=$DIM; [ "$SEVEN" -ge 75 ] && RC=$WC   # countdown takes the warning color once it matters
  [ -n "$SEVEN_AT" ] && SEG_WEEK="${SEG_WEEK}  ${RC}↻ $(countdown "$SEVEN_AT")${R}"
fi

LINE="${SEG_MODEL}"
[ -n "$SEG_GIT" ]  && LINE="${LINE}${SEP}${SEG_GIT}"
LINE="${LINE}${SEP}${SEG_CTX}"
[ -n "$SEG_WEEK" ] && LINE="${LINE}${SEP}${SEG_WEEK}"
LINE="${LINE}${SEP}${DIM}${CWD##*/}${R}"   # directory name, last and faint
printf '%s\n\342\200\213' "$LINE"
