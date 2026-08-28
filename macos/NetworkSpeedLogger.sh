#!/bin/sh

# Network Speed Logger for macOS
# Records combined receive/transmit traffic from active physical interfaces.

PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export PATH
LC_ALL=C
export LC_ALL

bytes_per_mb=1000000
duration_hours=24
sample_interval_seconds=15
language=Auto
list_adapters=false
manual_interfaces=
stop_requested=false
stop_reason=
fatal_message=
status_line_written=false
terminal_capture_enabled=false
terminal_state=
temp_dir=

script_dir=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd)
if [ -z "$script_dir" ]; then
    script_dir=$(pwd)
fi

append_manual_interface() {
    if [ -z "$manual_interfaces" ]; then
        manual_interfaces=$1
    else
        manual_interfaces="${manual_interfaces}
$1"
    fi
}

print_usage() {
    if [ "$is_chinese" = true ]; then
        cat <<'EOF'
用法：
  ./NetworkSpeedLogger.sh [选项]

选项：
  --duration-hours 小时           运行时长；0 表示仅手动停止（默认：24）
  --sample-interval-seconds 秒    采样间隔（默认：15，范围：1–3600）
  --adapter 接口名               手动监控接口，可重复指定（例如 en0、utun3）
  --language Auto|zh-CN|en-US    界面与汇总语言（默认：Auto）
  --list-adapters                 列出网络接口后退出
  -h, --help                      显示帮助

示例：
  ./NetworkSpeedLogger.sh
  ./NetworkSpeedLogger.sh --duration-hours 0
  ./NetworkSpeedLogger.sh --duration-hours 2 --sample-interval-seconds 5
  ./NetworkSpeedLogger.sh --list-adapters
  ./NetworkSpeedLogger.sh --adapter en0 --adapter en5
EOF
    else
        cat <<'EOF'
Usage:
  ./NetworkSpeedLogger.sh [options]

Options:
  --duration-hours HOURS          Duration; 0 means manual stop only (default: 24)
  --sample-interval-seconds SEC   Sample interval (default: 15, range: 1–3600)
  --adapter INTERFACE             Interface to monitor; repeat as needed (for example en0 or utun3)
  --language Auto|zh-CN|en-US    Terminal and summary language (default: Auto)
  --list-adapters                 List network interfaces and exit
  -h, --help                      Show this help

Examples:
  ./NetworkSpeedLogger.sh
  ./NetworkSpeedLogger.sh --duration-hours 0
  ./NetworkSpeedLogger.sh --duration-hours 2 --sample-interval-seconds 5
  ./NetworkSpeedLogger.sh --list-adapters
  ./NetworkSpeedLogger.sh --adapter en0 --adapter en5
EOF
    fi
}

parse_error() {
    printf '%s\n' "$1" >&2
    printf '%s\n' "Run with --help for usage. / 使用 --help 查看用法。" >&2
    exit 2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --duration-hours)
            [ "$#" -ge 2 ] || parse_error "Missing value for --duration-hours."
            duration_hours=$2
            shift 2
            ;;
        --duration-hours=*)
            duration_hours=${1#*=}
            shift
            ;;
        --sample-interval-seconds)
            [ "$#" -ge 2 ] || parse_error "Missing value for --sample-interval-seconds."
            sample_interval_seconds=$2
            shift 2
            ;;
        --sample-interval-seconds=*)
            sample_interval_seconds=${1#*=}
            shift
            ;;
        --adapter)
            [ "$#" -ge 2 ] || parse_error "Missing value for --adapter."
            append_manual_interface "$2"
            shift 2
            ;;
        --adapter=*)
            append_manual_interface "${1#*=}"
            shift
            ;;
        --language)
            [ "$#" -ge 2 ] || parse_error "Missing value for --language."
            language=$2
            shift 2
            ;;
        --language=*)
            language=${1#*=}
            shift
            ;;
        --list-adapters)
            list_adapters=true
            shift
            ;;
        -h|--help)
            help_requested=true
            shift
            ;;
        --)
            shift
            [ "$#" -eq 0 ] || parse_error "Unexpected positional arguments."
            ;;
        *)
            parse_error "Unknown option: $1"
            ;;
    esac
done

case "$language" in
    zh-CN)
        is_chinese=true
        ;;
    en-US)
        is_chinese=false
        ;;
    Auto|auto)
        preferred_language=$(defaults read -g AppleLanguages 2>/dev/null | awk -F '"' '/"/ { print $2; exit }')
        case "$preferred_language" in
            zh*) is_chinese=true ;;
            *) is_chinese=false ;;
        esac
        ;;
    *)
        parse_error "Invalid language: $language (expected Auto, zh-CN, or en-US)."
        ;;
esac

if [ "${help_requested:-false}" = true ]; then
    print_usage
    exit 0
fi

text() {
    if [ "$is_chinese" = true ]; then
        printf '%s' "$1"
    else
        printf '%s' "$2"
    fi
}

is_number_in_range() {
    awk -v value="$1" -v minimum="$2" -v maximum="$3" 'BEGIN {
        if (value !~ /^([0-9]+([.][0-9]*)?|[.][0-9]+)$/) exit 1
        number = value + 0
        exit !(number >= minimum && number <= maximum)
    }'
}

is_integer_in_range() {
    awk -v value="$1" -v minimum="$2" -v maximum="$3" 'BEGIN {
        if (value !~ /^[0-9]+$/) exit 1
        number = value + 0
        exit !(number >= minimum && number <= maximum)
    }'
}

if ! is_number_in_range "$duration_hours" 0 8760; then
    printf '%s\n' "$(text "运行时长必须是 0 到 8760 之间的数字。" "Duration hours must be a number from 0 through 8760.")" >&2
    exit 2
fi

if ! is_integer_in_range "$sample_interval_seconds" 1 3600; then
    printf '%s\n' "$(text "采样间隔必须是 1 到 3600 之间的整数秒。" "Sample interval must be an integer from 1 through 3600 seconds.")" >&2
    exit 2
fi

for required_command in networksetup ifconfig netstat awk date mktemp; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        printf '%s\n' "$(text "缺少 macOS 系统命令：$required_command" "Required macOS command not found: $required_command")" >&2
        exit 1
    fi
done

high_resolution_clock=false
if command -v perl >/dev/null 2>&1 &&
    perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e 'clock_gettime(CLOCK_MONOTONIC)' >/dev/null 2>&1; then
    high_resolution_clock=true
fi

now_seconds() {
    if [ "$high_resolution_clock" = true ]; then
        perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e 'printf "%.6f", clock_gettime(CLOCK_MONOTONIC)'
    else
        date +%s
    fi
}

temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/NetworkSpeedLogger.XXXXXX") || {
    printf '%s\n' "$(text "无法创建临时目录。" "Unable to create a temporary directory.")" >&2
    exit 1
}

hardware_map="$temp_dir/hardware"
current_interfaces="$temp_dir/current"
previous_snapshot="$temp_dir/previous"
current_snapshot="$temp_dir/snapshot"
query_interfaces="$temp_dir/query"
next_snapshot="$temp_dir/next"
observed_interfaces="$temp_dir/observed"
candidate_interfaces="$temp_dir/candidates"

: > "$observed_interfaces"

restore_terminal() {
    if [ "$terminal_capture_enabled" = true ] && [ -n "$terminal_state" ]; then
        stty "$terminal_state" <&3 2>/dev/null || true
        exec 3<&-
        exec 3>&-
        terminal_capture_enabled=false
    fi
}

cleanup() {
    restore_terminal
    if [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
        for temp_file in "$temp_dir"/*; do
            [ -e "$temp_file" ] && rm -f "$temp_file"
        done
        rmdir "$temp_dir" 2>/dev/null || true
    fi
}

trap cleanup EXIT

refresh_hardware_map() {
    networksetup -listallhardwareports 2>/dev/null | awk '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        function emit() {
            if (device != "") print device "|" port "|" address
            device = ""
            port = ""
            address = ""
        }
        /^Hardware Port:[[:space:]]*/ {
            emit()
            port = $0
            sub(/^Hardware Port:[[:space:]]*/, "", port)
            port = trim(port)
            next
        }
        /^Device:[[:space:]]*/ {
            device = $0
            sub(/^Device:[[:space:]]*/, "", device)
            device = trim(device)
            next
        }
        /^Ethernet Address:[[:space:]]*/ {
            address = $0
            sub(/^Ethernet Address:[[:space:]]*/, "", address)
            address = trim(address)
            next
        }
        END { emit() }
    ' > "$hardware_map"
}

is_known_virtual_interface() {
    case "$1" in
        lo*|gif*|stf*|utun*|ipsec*|ppp*|tun*|tap*|bridge*|awdl*|llw*|anpi*|ap*|p2p*|vmnet*|vboxnet*|wg*|fw*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_hardware_interface() {
    awk -F '|' -v target="$1" '$1 == target { found = 1 } END { exit !found }' "$hardware_map"
}

interface_is_active() {
    ifconfig "$1" 2>/dev/null | awk '
        /^[^[:space:]].*flags=.*<[^>]*UP[^>]*>/ { up = 1 }
        /^[[:space:]]*status:[[:space:]]*active[[:space:]]*$/ { active = 1 }
        END { exit !(up && active) }
    '
}

write_auto_interfaces() {
    output_path=$1
    refresh_hardware_map
    awk -F '|' 'NF >= 1 && $1 != "" { print $1 }' "$hardware_map" | sort -u > "$candidate_interfaces"
    : > "$output_path"
    while IFS= read -r interface_name; do
        [ -n "$interface_name" ] || continue
        if ! is_known_virtual_interface "$interface_name" && interface_is_active "$interface_name"; then
            printf '%s\n' "$interface_name" >> "$output_path"
        fi
    done < "$candidate_interfaces"
}

write_manual_interfaces() {
    output_path=$1
    printf '%s\n' "$manual_interfaces" | awk 'NF && !seen[$0]++' > "$output_path"
}

write_selected_interfaces() {
    if [ -n "$manual_interfaces" ]; then
        write_manual_interfaces "$1"
    else
        write_auto_interfaces "$1"
    fi
}

get_interface_counters() {
    interface_name=$1
    netstat -ibn -I "$interface_name" 2>/dev/null | awk -v target="$interface_name" '
        {
            if (input_column == 0 || output_column == 0) {
                for (column = 1; column <= NF; column++) {
                    if ($column == "Ibytes") input_column = column
                    if ($column == "Obytes") output_column = column
                }
                if ($1 == "Name") next
            }
            if ($1 == target && $3 ~ /^<Link#[0-9]+>$/ && input_column > 0 && output_column > 0) {
                if ($(input_column) ~ /^[0-9]+$/ && $(output_column) ~ /^[0-9]+$/) {
                    print $(input_column) "|" $(output_column)
                    exit
                }
            }
        }
    '
}

write_snapshot() {
    interfaces_path=$1
    output_path=$2
    : > "$output_path"
    while IFS= read -r interface_name; do
        [ -n "$interface_name" ] || continue
        counters=$(get_interface_counters "$interface_name")
        if [ -n "$counters" ]; then
            printf '%s|%s\n' "$interface_name" "$counters" >> "$output_path"
        fi
    done < "$interfaces_path"
}

interface_state() {
    interface_config=$(ifconfig "$1" 2>/dev/null) || {
        text "不可用" "unavailable"
        return
    }
    if printf '%s\n' "$interface_config" | awk '/^[^[:space:]].*flags=.*<[^>]*UP[^>]*>/ { up = 1 } /^[[:space:]]*status:[[:space:]]*active[[:space:]]*$/ { active = 1 } END { exit !(up && active) }'; then
        text "已连接" "active"
    elif printf '%s\n' "$interface_config" | awk '/^[^[:space:]].*flags=.*<[^>]*UP[^>]*>/ { found = 1 } END { exit !found }'; then
        text "已启用" "up"
    else
        text "未连接" "inactive"
    fi
}

print_adapter_list() {
    refresh_hardware_map
    all_interfaces=$(ifconfig -l 2>/dev/null)
    if [ "$is_chinese" = true ]; then
        printf '%-12s %-10s %-10s %-28s %s\n' "接口名" "状态" "自动监控" "硬件端口" "MAC 地址"
    else
        printf '%-12s %-12s %-10s %-28s %s\n' "Interface" "Status" "Automatic" "Hardware Port" "MAC Address"
    fi
    for interface_name in $all_interfaces; do
        hardware_record=$(awk -F '|' -v target="$interface_name" '$1 == target { print; exit }' "$hardware_map")
        hardware_port=$(printf '%s' "$hardware_record" | awk -F '|' '{ print $2 }')
        hardware_address=$(printf '%s' "$hardware_record" | awk -F '|' '{ print $3 }')
        automatic=no
        if [ -n "$hardware_record" ] && ! is_known_virtual_interface "$interface_name"; then
            automatic=yes
        fi
        state=$(interface_state "$interface_name")
        [ -n "$hardware_port" ] || hardware_port="-"
        [ -n "$hardware_address" ] || hardware_address="-"
        if [ "$is_chinese" = true ]; then
            [ "$automatic" = yes ] && automatic_text="是" || automatic_text="否"
            printf '%-12s %-10s %-10s %-28s %s\n' "$interface_name" "$state" "$automatic_text" "$hardware_port" "$hardware_address"
        else
            printf '%-12s %-12s %-10s %-28s %s\n' "$interface_name" "$state" "$automatic" "$hardware_port" "$hardware_address"
        fi
    done
}

if [ "$list_adapters" = true ]; then
    print_adapter_list
    exit 0
fi

if [ -n "$manual_interfaces" ]; then
    printf '%s\n' "$manual_interfaces" | while IFS= read -r interface_name; do
        [ -n "$interface_name" ] || continue
        if ! ifconfig "$interface_name" >/dev/null 2>&1; then
            printf '%s\n' "$(text "找不到网络接口：$interface_name。请使用 --list-adapters 查看接口名。" "Network interface not found: $interface_name. Use --list-adapters to view interface names.")" >&2
            exit 9
        fi
    done
    manual_validation_status=$?
    [ "$manual_validation_status" -eq 0 ] || exit 1
fi

write_selected_interfaces "$current_interfaces"
if [ ! -s "$current_interfaces" ]; then
    printf '%s\n' "$(text "没有找到可监控的已连接物理网卡。请先连接网络，或使用 --list-adapters 查看接口名并用 --adapter 手动指定。" "No connected physical interface was found. Connect to a network, or use --list-adapters and select an interface with --adapter.")" >&2
    exit 1
fi

write_snapshot "$current_interfaces" "$previous_snapshot"
if [ ! -s "$previous_snapshot" ]; then
    printf '%s\n' "$(text "无法读取所选接口的流量计数器。请确认接口处于启用状态。" "Unable to read traffic counters for the selected interfaces. Make sure they are enabled.")" >&2
    exit 1
fi

while IFS= read -r interface_name; do
    [ -n "$interface_name" ] && printf '%s\n' "$interface_name" >> "$observed_interfaces"
done < "$current_interfaces"

start_time_seconds=$(now_seconds)
start_time_display=$(date '+%Y-%m-%d %H:%M:%S %z' | sed -E 's/([+-][0-9]{2})([0-9]{2})$/\1:\2/')
file_stamp=$(date '+%Y%m%d_%H%M%S')
file_base="NetworkSpeed_$file_stamp"
csv_path="$script_dir/$file_base.csv"
summary_path="$script_dir/${file_base}_summary.md"

suffix=1
while [ -e "$csv_path" ] || [ -e "$summary_path" ]; do
    csv_path="$script_dir/${file_base}_$suffix.csv"
    summary_path="$script_dir/${file_base}_${suffix}_summary.md"
    suffix=$((suffix + 1))
done

if ! printf '\357\273\277%s\n' 'Timestamp,ElapsedSeconds,Download_MBps,Upload_MBps,ActiveAdapters' > "$csv_path"; then
    printf '%s\n' "$(text "无法创建 CSV 文件：$csv_path" "Unable to create CSV file: $csv_path")" >&2
    exit 1
fi

sample_count=0
total_received_bytes=0
total_sent_bytes=0
total_measured_seconds=0
min_download=
max_download=0
min_upload=
max_upload=0
last_sample_elapsed=0
target_seconds=$(awk -v hours="$duration_hours" 'BEGIN { printf "%.6f", hours * 3600 }')
if awk -v hours="$duration_hours" 'BEGIN { exit !(hours > 0) }'; then
    duration_limited=true
else
    duration_limited=false
fi

duration_stop_reason=$(text "达到设定时长" "Duration reached")
manual_stop_reason=$(text "用户手动停止" "Stopped by user")
signal_stop_reason=$(text "收到终止信号" "Termination signal received")
stop_reason=$duration_stop_reason

request_manual_stop() {
    stop_requested=true
    stop_reason=$manual_stop_reason
}

request_signal_stop() {
    stop_requested=true
    stop_reason=$signal_stop_reason
}

trap request_manual_stop INT
trap request_signal_stop TERM HUP

if [ -t 0 ] && [ -r /dev/tty ]; then
    if exec 3<>/dev/tty; then
        terminal_state=$(stty -g <&3 2>/dev/null)
        if [ -n "$terminal_state" ] && stty -echo -icanon min 0 time 10 <&3 2>/dev/null; then
            terminal_capture_enabled=true
        fi
    fi
fi

wait_until_epoch() {
    wait_target=$1
    while :; do
        [ "$stop_requested" = false ] || return 1
        wait_now=$(now_seconds)
        remaining_wait=$(awk -v target="$wait_target" -v now="$wait_now" 'BEGIN { printf "%.6f", target - now }')
        if awk -v remaining="$remaining_wait" 'BEGIN { exit !(remaining <= 0) }'; then
            return 0
        fi

        if [ "$terminal_capture_enabled" = true ]; then
            wait_deciseconds=$(awk -v remaining="$remaining_wait" 'BEGIN {
                value = int(remaining * 10)
                if (value < remaining * 10) value++
                if (value < 1) value = 1
                if (value > 10) value = 10
                print value
            }')
            stty min 0 time "$wait_deciseconds" <&3 2>/dev/null || true
            pressed_key=$(dd bs=1 count=1 <&3 2>/dev/null)
            case "$pressed_key" in
                q|Q)
                    request_manual_stop
                    return 1
                    ;;
            esac
        else
            sleep "$remaining_wait"
        fi
    done
}

join_interface_names() {
    sort -u "$1" | awk 'NF { if (count++) printf "; "; printf "%s", $0 } END { if (!count) printf "(none)" }'
}

join_observed_names() {
    separator=$1
    sort -u "$observed_interfaces" | awk -v separator="$separator" 'NF { if (count++) printf "%s", separator; printf "%s", $0 }'
}

if [ "$is_chinese" = true ]; then
    name_separator="、"
else
    name_separator=", "
fi

initial_names=$(join_observed_names "$name_separator")
if [ -t 1 ]; then
    printf '\033[32m%s\033[0m\n' "$(text "网络速度监控已启动" "Network speed monitoring started")"
else
    printf '%s\n' "$(text "网络速度监控已启动" "Network speed monitoring started")"
fi
printf '%s%s\n' "$(text "监控接口：" "Interfaces: ")" "$initial_names"
if awk -v hours="$duration_hours" 'BEGIN { exit !(hours > 0) }'; then
    printf '%s%s%s%s%s\n' "$(text "计划时长：" "Planned duration: ")" "$duration_hours" "$(text " 小时；采样间隔：" " hours; sample interval: ")" "$sample_interval_seconds" "$(text " 秒" " seconds")"
else
    printf '%s%s%s%s\n' "$(text "计划时长：不限；采样间隔：" "Planned duration: unlimited; sample interval: ")" "$sample_interval_seconds" "$(text " 秒" " seconds")" ""
fi
printf '%s%s\n' "$(text "CSV：" "CSV: ")" "$csv_path"
if [ "$terminal_capture_enabled" = true ]; then
    printf '%s\n' "$(text "按 Ctrl+C 或 Q 可提前停止并生成汇总。" "Press Ctrl+C or Q to stop early and generate the summary.")"
else
    printf '%s\n' "$(text "按 Ctrl+C 可提前停止并生成汇总。" "Press Ctrl+C to stop early and generate the summary.")"
fi

while :; do
    elapsed_before_wait=$(awk -v now="$(now_seconds)" -v start="$start_time_seconds" 'BEGIN {
        value = now - start
        if (value < 0) value = 0
        printf "%.6f", value
    }')
    if [ "$duration_limited" = true ]; then
        if awk -v elapsed="$elapsed_before_wait" -v target="$target_seconds" 'BEGIN { exit !(elapsed >= target) }'; then
            break
        fi
    fi

    sleep_seconds=$sample_interval_seconds
    if [ "$duration_limited" = true ]; then
        sleep_seconds=$(awk -v interval="$sleep_seconds" -v elapsed="$elapsed_before_wait" -v target="$target_seconds" 'BEGIN {
            remaining = target - elapsed
            if (remaining < interval) interval = remaining
            if (interval < 0) interval = 0
            printf "%.6f", interval
        }')
    fi

    wait_target=$(awk -v now="$(now_seconds)" -v seconds="$sleep_seconds" 'BEGIN { printf "%.6f", now + seconds }')
    wait_until_epoch "$wait_target" || true

    write_selected_interfaces "$current_interfaces"
    while IFS= read -r interface_name; do
        [ -n "$interface_name" ] && printf '%s\n' "$interface_name" >> "$observed_interfaces"
    done < "$current_interfaces"

    {
        awk -F '|' 'NF { print $1 }' "$previous_snapshot"
        cat "$current_interfaces"
    } | awk 'NF && !seen[$0]++' > "$query_interfaces"

    write_snapshot "$query_interfaces" "$current_snapshot"

    current_elapsed=$(awk -v now="$(now_seconds)" -v start="$start_time_seconds" 'BEGIN {
        value = now - start
        if (value < 0) value = 0
        printf "%.6f", value
    }')
    actual_interval=$(awk -v current="$current_elapsed" -v previous="$last_sample_elapsed" 'BEGIN { printf "%.6f", current - previous }')
    if awk -v interval="$actual_interval" 'BEGIN { exit !(interval <= 0) }'; then
        [ "$stop_requested" = true ] && break
        continue
    fi
    last_sample_elapsed=$current_elapsed

    deltas=$(awk -F '|' '
        NR == FNR { received[$1] = $2; sent[$1] = $3; next }
        ($1 in received) {
            if ($2 >= received[$1]) received_delta += $2 - received[$1]
            if ($3 >= sent[$1]) sent_delta += $3 - sent[$1]
        }
        END { printf "%.0f|%.0f", received_delta, sent_delta }
    ' "$previous_snapshot" "$current_snapshot")
    received_delta=${deltas%%|*}
    sent_delta=${deltas#*|}

    awk -F '|' 'NR == FNR { line[$1] = $0; next } ($1 in line) { print line[$1] }' "$current_snapshot" "$current_interfaces" > "$next_snapshot"
    cp "$next_snapshot" "$previous_snapshot"

    download_mbps=$(awk -v bytes="$received_delta" -v seconds="$actual_interval" -v unit="$bytes_per_mb" 'BEGIN { printf "%.12f", (bytes / unit) / seconds }')
    upload_mbps=$(awk -v bytes="$sent_delta" -v seconds="$actual_interval" -v unit="$bytes_per_mb" 'BEGIN { printf "%.12f", (bytes / unit) / seconds }')

    sample_count=$((sample_count + 1))
    total_received_bytes=$(awk -v total="$total_received_bytes" -v delta="$received_delta" 'BEGIN { printf "%.0f", total + delta }')
    total_sent_bytes=$(awk -v total="$total_sent_bytes" -v delta="$sent_delta" 'BEGIN { printf "%.0f", total + delta }')
    total_measured_seconds=$(awk -v total="$total_measured_seconds" -v interval="$actual_interval" 'BEGIN { printf "%.6f", total + interval }')

    speed_extremes=$(awk -v down="$download_mbps" -v up="$upload_mbps" -v min_down="${min_download:-$download_mbps}" -v max_down="$max_download" -v min_up="${min_upload:-$upload_mbps}" -v max_up="$max_upload" 'BEGIN {
        if (down < min_down) min_down = down
        if (down > max_down) max_down = down
        if (up < min_up) min_up = up
        if (up > max_up) max_up = up
        printf "%.12f|%.12f|%.12f|%.12f", min_down, max_down, min_up, max_up
    }')
    min_download=${speed_extremes%%|*}
    remaining_extremes=${speed_extremes#*|}
    max_download=${remaining_extremes%%|*}
    remaining_extremes=${remaining_extremes#*|}
    min_upload=${remaining_extremes%%|*}
    max_upload=${remaining_extremes#*|}

    active_names=$(join_interface_names "$current_interfaces")
    csv_safe_names=$(printf '%s' "$active_names" | sed 's/"/""/g')
    sample_timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z' | sed -E 's/([+-][0-9]{2})([0-9]{2})$/\1:\2/')
    if ! printf '%s,%.3f,%.6f,%.6f,"%s"\n' "$sample_timestamp" "$current_elapsed" "$download_mbps" "$upload_mbps" "$csv_safe_names" >> "$csv_path"; then
        fatal_message=$(text "写入 CSV 时发生错误。" "An error occurred while writing the CSV file.")
        stop_reason="$(text "发生错误：" "Error: ")$fatal_message"
        break
    fi

    status_timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if [ "$is_chinese" = true ]; then
        status=$(printf '%s | 下载 %10.3f MB/s | 上传 %10.3f MB/s | 样本 %s' "$status_timestamp" "$download_mbps" "$upload_mbps" "$sample_count")
    else
        status=$(printf '%s | Down %10.3f MB/s | Up %10.3f MB/s | Samples %s' "$status_timestamp" "$download_mbps" "$upload_mbps" "$sample_count")
    fi
    printf '\r%-100s' "$status"
    status_line_written=true

    [ "$stop_requested" = true ] && break
done

restore_terminal
end_time_seconds=$(now_seconds)
end_time_display=$(date '+%Y-%m-%d %H:%M:%S %z' | sed -E 's/([+-][0-9]{2})([0-9]{2})$/\1:\2/')
run_seconds=$(awk -v end="$end_time_seconds" -v start="$start_time_seconds" 'BEGIN {
    value = end - start
    if (value < 0) value = 0
    printf "%.6f", value
}')

if [ "$status_line_written" = true ]; then
    printf '\n'
fi

if [ "$sample_count" -gt 0 ] && awk -v seconds="$total_measured_seconds" 'BEGIN { exit !(seconds > 0) }'; then
    average_download=$(awk -v bytes="$total_received_bytes" -v seconds="$total_measured_seconds" -v unit="$bytes_per_mb" 'BEGIN { printf "%.3f", (bytes / unit) / seconds }')
    average_upload=$(awk -v bytes="$total_sent_bytes" -v seconds="$total_measured_seconds" -v unit="$bytes_per_mb" 'BEGIN { printf "%.3f", (bytes / unit) / seconds }')
else
    average_download=0.000
    average_upload=0.000
    min_download=0
    min_upload=0
fi

min_download_text=$(awk -v value="${min_download:-0}" 'BEGIN { printf "%.3f", value }')
max_download_text=$(awk -v value="$max_download" 'BEGIN { printf "%.3f", value }')
min_upload_text=$(awk -v value="${min_upload:-0}" 'BEGIN { printf "%.3f", value }')
max_upload_text=$(awk -v value="$max_upload" 'BEGIN { printf "%.3f", value }')
download_total_text=$(awk -v bytes="$total_received_bytes" -v unit="$bytes_per_mb" 'BEGIN { printf "%.3f", bytes / unit }')
upload_total_text=$(awk -v bytes="$total_sent_bytes" -v unit="$bytes_per_mb" 'BEGIN { printf "%.3f", bytes / unit }')

format_duration() {
    duration_value=$1
    days=$((duration_value / 86400))
    hours=$(((duration_value % 86400) / 3600))
    minutes=$(((duration_value % 3600) / 60))
    seconds=$((duration_value % 60))
    if [ "$days" -gt 0 ]; then
        printf '%s%s%02d:%02d:%02d' "$days" "$(text " 天 " " d ")" "$hours" "$minutes" "$seconds"
    else
        printf '%02d:%02d:%02d' "$hours" "$minutes" "$seconds"
    fi
}

run_seconds_display=$(awk -v value="$run_seconds" 'BEGIN { printf "%d", value }')
duration_text=$(format_duration "$run_seconds_display")
adapter_summary=$(join_observed_names "$name_separator")
adapter_summary_markdown=$(printf '%s' "$adapter_summary" | sed 's/|/\\|/g')
csv_filename=${csv_path##*/}

if [ "$is_chinese" = true ]; then
    if ! {
        printf '\357\273\277# 网络速度监控汇总\n\n'
        printf '%s\n' "- 开始时间：$start_time_display"
        printf '%s\n' "- 结束时间：$end_time_display"
        printf '%s\n' "- 实际运行时间：$duration_text"
        printf '%s\n' "- 结束原因：$stop_reason"
        printf '%s\n' "- 采样间隔：$sample_interval_seconds 秒"
        printf '%s\n' "- 有效样本数：$sample_count"
        printf '%s\n' "- 监控过的接口：$adapter_summary_markdown"
        printf '%s\n\n' "- 详细记录：$csv_filename"
        printf '| 指标 | 下载 | 上传 |\n'
        printf '|---|---:|---:|\n'
        printf '| 最小速度 | %s MB/s | %s MB/s |\n' "$min_download_text" "$min_upload_text"
        printf '| 最大速度 | %s MB/s | %s MB/s |\n' "$max_download_text" "$max_upload_text"
        printf '| 平均速度 | %s MB/s | %s MB/s |\n' "$average_download" "$average_upload"
        printf '| 总数据量 | %s MB | %s MB |\n\n' "$download_total_text" "$upload_total_text"
        printf '> 速度使用十进制 MB/s（1 MB = 1,000,000 字节）。数据为所监控接口的实际收发流量，包含互联网和局域网流量。\n'
    } > "$summary_path"; then
        printf '%s\n' "无法写入汇总文件：$summary_path" >&2
        exit 1
    fi
else
    if ! {
        printf '\357\273\277# Network Speed Monitoring Summary\n\n'
        printf '%s\n' "- Start time: $start_time_display"
        printf '%s\n' "- End time: $end_time_display"
        printf '%s\n' "- Actual duration: $duration_text"
        printf '%s\n' "- Stop reason: $stop_reason"
        printf '%s\n' "- Sample interval: $sample_interval_seconds seconds"
        printf '%s\n' "- Valid samples: $sample_count"
        printf '%s\n' "- Monitored interfaces: $adapter_summary_markdown"
        printf '%s\n\n' "- Detailed log: $csv_filename"
        printf '| Metric | Download | Upload |\n'
        printf '|---|---:|---:|\n'
        printf '| Minimum speed | %s MB/s | %s MB/s |\n' "$min_download_text" "$min_upload_text"
        printf '| Maximum speed | %s MB/s | %s MB/s |\n' "$max_download_text" "$max_upload_text"
        printf '| Average speed | %s MB/s | %s MB/s |\n' "$average_download" "$average_upload"
        printf '| Total data | %s MB | %s MB |\n\n' "$download_total_text" "$upload_total_text"
        printf '> Speeds use decimal MB/s (1 MB = 1,000,000 bytes). Values are actual monitored-interface traffic and include both internet and local-network traffic.\n'
    } > "$summary_path"; then
        printf '%s\n' "Unable to write summary file: $summary_path" >&2
        exit 1
    fi
fi

printf '%s\n' "$(text "网络速度监控已结束" "Network speed monitoring finished")"
printf '%s%s\n' "$(text "结束原因：" "Stop reason: ")" "$stop_reason"
printf '%s%s%s%s\n' "$(text "实际运行时间：" "Actual duration: ")" "$duration_text" "$(text "；样本数：" "; samples: ")" "$sample_count"
printf '%s\n' "$(text "下载：最小 $min_download_text，最大 $max_download_text，平均 $average_download MB/s" "Download: min $min_download_text, max $max_download_text, average $average_download MB/s")"
printf '%s\n' "$(text "上传：最小 $min_upload_text，最大 $max_upload_text，平均 $average_upload MB/s" "Upload: min $min_upload_text, max $max_upload_text, average $average_upload MB/s")"
printf '%s%s\n' "$(text "CSV：" "CSV: ")" "$csv_path"
printf '%s%s\n' "$(text "汇总：" "Summary: ")" "$summary_path"

if [ -n "$fatal_message" ]; then
    printf '%s\n' "$fatal_message" >&2
    exit 1
fi
