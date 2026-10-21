input="$(cat)"

IFS=$'\x1f' read -r model effort ctx cost cwd h5 h5_reset d7 d7_reset < <(
  jq -r '[
    .model.display_name,
    (.effort.level // ""),
    (.context_window.used_percentage // ""),
    (.cost.total_cost_usd // 0),
    .workspace.current_dir,
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // "")
  ] | map(tostring) | join("\u001f")' <<<"$input"
)

red=$'\e[31m'
yellow=$'\e[33m'
green=$'\e[32m'
dim=$'\e[2m'
reset=$'\e[0m'
sep=" ${dim}│${reset} "

color() {
  local pct=${1%.*}
  if ((pct >= 80)); then
    printf '%s' "$red"
  elif ((pct >= 50)); then
    printf '%s' "$yellow"
  else
    printf '%s' "$green"
  fi
}

until_reset() {
  local at=$1 now left
  now=$(date +%s)
  left=$((at - now))
  ((left < 0)) && left=0
  if ((left >= 86400)); then
    printf '%dd%dh' $((left / 86400)) $((left % 86400 / 3600))
  elif ((left >= 3600)); then
    printf '%dh%dm' $((left / 3600)) $((left % 3600 / 60))
  else
    printf '%dm' $((left / 60))
  fi
}

out="$model"
[[ -n $effort ]] && out+=" ${dim}·${reset} $effort"

if [[ -n $ctx ]]; then
  out+="${sep}ctx $(color "$ctx")$(printf '%.0f' "$ctx")%${reset}"
else
  out+="${sep}ctx –"
fi

limits=()
if [[ -n $h5 ]]; then
  limits+=("5h $(color "$h5")$(printf '%.0f' "$h5")%${reset}${h5_reset:+ ${dim}$(until_reset "${h5_reset%.*}")${reset}}")
fi
if [[ -n $d7 ]]; then
  limits+=("7d $(color "$d7")$(printf '%.0f' "$d7")%${reset}${d7_reset:+ ${dim}$(until_reset "${d7_reset%.*}")${reset}}")
fi
if ((${#limits[@]})); then
  out+="${sep}${limits[0]}"
  ((${#limits[@]} > 1)) && out+=" ${dim}·${reset} ${limits[1]}"
fi

out+="${sep}$(printf '$%.2f' "$cost")"
out+="${sep}${cwd/#$HOME/\~}"

if stat="$(git -C "$cwd" --no-optional-locks diff HEAD --shortstat 2>/dev/null)" && [[ -n $stat ]]; then
  added=0
  removed=0
  [[ $stat =~ ([0-9]+)\ insertion ]] && added=${BASH_REMATCH[1]}
  [[ $stat =~ ([0-9]+)\ deletion ]] && removed=${BASH_REMATCH[1]}
  out+="${sep}${green}+${added}${reset} ${red}−${removed}${reset}"
fi

printf '%s\n' "$out"
