#!/bin/bash

input=$(cat)

# Colors
R='\033[0m'
B='\033[1m'
CY='\033[36m'
GR='\033[32m'
YE='\033[33m'
MA='\033[35m'
BL='\033[34m'
WH='\033[37m'
RD='\033[31m'

# ── 从父进程链解析 --model 参数（用于 ept 启动的场景） ──
get_model_from_parent_chain() {
    local current_pid=$$
    local max_depth=3

    for i in $(seq 1 $max_depth); do
        local ppid=$(ps -p $current_pid -o ppid= 2>/dev/null | tr -d ' ')
        [[ -z "$ppid" || "$ppid" == "0" ]] && break

        local cmd=$(ps -p $ppid -o args= 2>/dev/null)
        # 检查是否有 --model 参数
        if echo "$cmd" | grep -qE "\-\-model"; then
            echo "$cmd" | sed 's/.*--model \([^ ]*\).*/\1/'
            return 0
        fi

        current_pid=$ppid
    done
    return 1
}

# ── 模型显示：优先从 CLAUDE_MODEL_LABEL 环境变量，其次从父进程链解析，其次 settings.json ──
if [[ -n "$CLAUDE_MODEL_LABEL" ]]; then
    model_display="$CLAUDE_MODEL_LABEL"
elif [[ -n "$CLAUDE_MODEL" ]]; then
    model_display="$CLAUDE_MODEL"
elif [[ -n "$ANTHROPIC_MODEL" ]]; then
    model_display="$ANTHROPIC_MODEL"
else
    # 尝试从父进程链解析 --model 参数（ept 场景）
    if model_display=$(get_model_from_parent_chain); then
        : # 成功获取到模型名
    else
        SETTINGS_FILE="$HOME/.claude/settings.json"
        if [[ -f "$SETTINGS_FILE" ]]; then
            model_display=$(jq -r '.model // "unknown"' "$SETTINGS_FILE")
        else
            model_display="unknown"
        fi
    fi
fi

case "$model_display" in
    *opus*)   model_color="\033[1;35m" ;;  # 紫色
    *sonnet*) model_color="\033[1;34m" ;;  # 蓝色
    *haiku*)  model_color="\033[1;32m" ;;  # 绿色
    *minimax*|*glm*) model_color="\033[1;33m" ;;  # 黄色
    *)        model_color="\033[1;37m" ;;  # 白色
esac

# ── 从 JSON 读取其余字段 ──
cwd=$(echo "$input" | jq -r '.cwd // empty')
total_in=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
total_out=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
cache_write=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
raw_input=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
api_ms=$(echo "$input" | jq -r '.cost.total_api_duration_ms // 0')
transcript=$(echo "$input" | jq -r '.transcript_path // empty')

ctx_used=$((ctx_size * used_pct / 100))
total_cache_input=$((cache_read + cache_write + raw_input))
if [ "$total_cache_input" -gt 0 ]; then
  cache_hit_rate=$((cache_read * 100 / total_cache_input))
else
  cache_hit_rate=0
fi

format_tokens() {
  local n=${1:-0}
  n=${n//[^0-9]/}
  n=${n:-0}
  if [ "$n" -ge 1000000 ]; then
    printf "%d.%dM" "$((n / 1000000))" "$(( (n % 1000000) / 100000 ))"
  elif [ "$n" -ge 1000 ]; then
    printf "%d.%dk" "$((n / 1000))" "$(( (n % 1000) / 100 ))"
  else
    echo "$n"
  fi
}

format_duration() {
  local ms=$1
  local s=$((ms / 1000))
  local min=$((s / 60))
  local hr=$((s / 3600))
  if [ "$hr" -gt 0 ]; then
    printf "%dh%dm" "$hr" "$((min % 60))"
  elif [ "$min" -gt 0 ]; then
    printf "%dm" "$min"
  else
    printf "%ds" "$s"
  fi
}

format_duration_short() {
  local ms=$1
  local s=$((ms / 1000))
  local min=$((s / 60))
  local hr=$((s / 3600))
  if [ "$hr" -gt 0 ]; then
    printf "%dh%dm" "$hr" "$((min % 60))"
  else
    printf "%dm" "$min"
  fi
}

parse_features() {
  local file=$1
  [ -z "$file" ] || [ ! -f "$file" ] && return

  local counts
  counts=$(jq -r '.message.content[]? | select(.type == "tool_use") | .name' "$file" 2>/dev/null \
    | sed 's/^mcp__.*/mcp/' \
    | sort | uniq -c | sort -rn)
  [ -z "$counts" ] && return

  local advanced="Agent Skill TaskCreate TaskUpdate EnterPlanMode EnterWorktree WebSearch NotebookEdit CronCreate CronDelete ScheduleWakeup mcp"
  local parts=""
  while read -r count tool; do
    local is_advanced=false
    for a in $advanced; do [ "$tool" = "$a" ] && is_advanced=true && break; done
    [ "$is_advanced" = false ] && continue

    local name
    case "$tool" in
      Agent)          name="agent" ;;
      Skill)          name="skill" ;;
      TaskCreate)     name="task+" ;;
      TaskUpdate)     name="task~" ;;
      EnterPlanMode)  name="plan" ;;
      EnterWorktree)  name="wt" ;;
      WebSearch)      name="web" ;;
      NotebookEdit)   name="nb" ;;
      CronCreate|CronDelete) name="cron" ;;
      ScheduleWakeup) name="loop" ;;
      mcp)            name="mcp" ;;
      *)              continue ;;
    esac
    parts="${parts:+${parts} }${name}×${count}"
  done <<< "$counts"

  echo "$parts"
}

cache_color() {
  local rate=${1:-0}
  rate=${rate//[^0-9]/}
  rate=${rate:-0}
  if [ "$rate" -ge 80 ]; then printf '%s' "$GR"
  elif [ "$rate" -ge 40 ]; then printf '%s' "$YE"
  else printf '%s' "$RD"
  fi
}

token_color() {
  local pct=${1:-0}
  pct=${pct//[^0-9]/}
  pct=${pct:-0}
  if [ "$pct" -ge 80 ]; then printf '%s' "$RD"
  elif [ "$pct" -ge 50 ]; then printf '%s' "$YE"
  else printf '%s' "$GR"
  fi
}

ctx_used_fmt=$(format_tokens "$ctx_used")
ctx_fmt=$(format_tokens "$ctx_size")
duration_fmt=$(format_duration "$duration_ms")
api_fmt=$(format_duration_short "$api_ms")
tc=$(token_color "$used_pct")
cc=$(cache_color "$cache_hit_rate")

cwd_short="${cwd/#$HOME/~}"

branch=$(git -C "$cwd" branch --show-current 2>/dev/null || echo "")
branch_part=""
[ -n "$branch" ] && branch_part=" ${MA}${branch}${R}"

features=$(parse_features "$transcript")
feature_part=""
[ -n "$features" ] && feature_part=" ${BL}${features}${R}"

S=" ${WH}|${R} "

echo -e "${model_color}${B}[${model_display}]${R}${S}${tc}${ctx_used_fmt}/${ctx_fmt}${R}${S}${YE}${duration_fmt}${R}[api:${YE}${api_fmt}${R}]${S}${cc}cache:${cache_hit_rate}%${R}"
echo -e "${MA}${cwd_short}${R}${branch_part}"
[ -n "$features" ] && echo -e "${BL}${features}${R}"

exit 0
