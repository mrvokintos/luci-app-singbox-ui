#!/bin/sh

# Shared UI helpers for install scripts.
# Scripts may override palette/symbols before sourcing this file.

: "${FG_ACCENT:=\033[38;5;85m}"
: "${FG_WARNING:=\033[38;5;214m}"
: "${FG_SUCCESS:=\033[38;5;41m}"
: "${FG_ERROR:=\033[38;5;203m}"
: "${RESET:=\033[0m}"
: "${FG_USER_COLOR:=\033[38;5;117m}"

: "${SEP_CHAR:=-}"
: "${ARROW:=▸}"
: "${ARROW_CLEAR:=>}"
: "${CHECK:=✓}"
: "${CROSS:=✗}"
: "${INDENT:=  }"

# Прогресс / Progress
show_progress() {
    echo -e "${INDENT}${ARROW} ${FG_ACCENT}$1${RESET}"
}

# Успех / Success
show_success() {
    echo -e "${INDENT}${CHECK} ${FG_SUCCESS}$1${RESET}\n"
}

# Ошибка / Error
show_error() {
    echo -e "${INDENT}${CROSS} ${FG_ERROR}$1${RESET}\n"
}

# Предупреждение / Warning
show_warning() {
    echo -e "${INDENT}! ${FG_WARNING}$1${RESET}\n"
}

# Сообщение / Message
show_message() {
    echo -e "${FG_USER_COLOR}${INDENT}${ARROW} $1${RESET}"
}

# Ввод / Input
read_input() {
    echo -ne "${FG_USER_COLOR}${INDENT}${ARROW_CLEAR} $1${RESET} "
    if [ -n "$2" ]; then
        read -r "$2"
    else
        read -r REPLY
    fi
}

# Ввод скрытый / Input hidden
read_input_secret() {
    echo -ne "${FG_USER_COLOR}${INDENT}${ARROW_CLEAR} $1${RESET} "
    if [ -n "$2" ]; then
        read -s "$2"
    else
        read -s REPLY
    fi
    echo
}

# ── Меню выбора / Choice menu ───────────────────────────────────────────────
# ui_choose VAR "Title" DEFAULT "Label 1" "Label 2" ...
# Сохраняет номер выбранного пункта (1..N) в VAR.
# В терминале: стрелки ↑/↓ (или j/k), Enter — выбрать, цифра — сразу выбрать.
# Без терминала или при UI_PLAIN=1 — обычный ввод номера.
# Stores the selected item number (1..N) in VAR. Arrow keys / j / k move,
# Enter selects, a digit selects at once. Falls back to typed numbers when not
# on a terminal or when UI_PLAIN=1.
# Пункты могут начинаться с "1." или "1)": номер убирается, меню рисует свой.
: "${UI_MENU_ROWS:=10}"

ui_tty() {
    [ "${UI_PLAIN:-0}" != 1 ] && [ -t 0 ] && [ -t 1 ] || return 1
    case "${TERM:-dumb}" in dumb) return 1 ;; esac
    return 0
}

_ui_strip_num() {
    printf '%s' "$1" | sed 's/^[[:space:]]*[0-9]\{1,\}[.)][[:space:]]*//'
}

# _ui_item N "$@" — N-й пункт из списка после N / Nth item of the list after N
_ui_item() {
    eval "printf '%s' \"\${$(($1 + 1))}\""
}

_ui_choose_plain() {
    local title="$1" def="$2" n i label answer hint
    shift 2
    n=$#
    if [ -n "$def" ]; then hint="[1-$n, Enter=$def]"; else hint="[1-$n]"; fi
    while true; do
        show_message "$title"
        i=1
        for label in "$@"; do
            show_message "$i. $(_ui_strip_num "$label")"
            i=$((i + 1))
        done
        read_input "$hint:" answer
        answer="${answer:-$def}"
        case "$answer" in
            ''|*[!0-9]*) ;;
            *)
                if [ "$answer" -ge 1 ] && [ "$answer" -le "$n" ]; then
                    _UI_SEL=$answer
                    return 0
                fi
                ;;
        esac
        show_error "${MSG_INVALID_INPUT:-Invalid choice / Неверный выбор}"
    done
}

_ui_tty_restore() {
    printf '\033[?25h\033[?7h'
}

_ui_choose_tty() {
    local title="$1" sel="${2:-1}" n rows off first=1 i end key rest label esc hint saved_traps
    shift 2
    n=$#
    [ "$sel" -ge 1 ] 2>/dev/null && [ "$sel" -le "$n" ] || sel=1
    rows=$UI_MENU_ROWS
    [ "$n" -lt "$rows" ] && rows=$n
    off=1
    esc=$(printf '\033')
    if [ "$n" -le 9 ]; then hint="↑/↓ Enter · 1-$n"; else hint="↑/↓ Enter"; fi

    saved_traps=$(trap)
    trap '_ui_tty_restore; exit 130' INT TERM HUP
    # Без переноса строк и без курсора, чтобы перерисовка не съезжала.
    # No line wrap and no cursor so redraws stay aligned.
    printf '\033[?7l\033[?25l'

    while true; do
        [ "$sel" -lt "$off" ] && off=$sel
        [ "$sel" -ge $((off + rows)) ] && off=$((sel - rows + 1))
        [ "$first" = 1 ] || printf '\033[%dA' $((rows + 2))
        first=0
        printf '\r\033[J'
        printf '%s%b? %s%b\n' "$INDENT" "$FG_USER_COLOR" "$title" "$RESET"
        i=$off
        end=$((off + rows - 1))
        while [ "$i" -le "$end" ]; do
            label=$(_ui_strip_num "$(_ui_item "$i" "$@")")
            if [ "$i" = "$sel" ]; then
                printf '%s%b\033[7m ❯ %2d. %s \033[0m\n' "$INDENT" "$FG_ACCENT" "$i" "$label"
            else
                printf '%s   %2d. %s\n' "$INDENT" "$i" "$label"
            fi
            i=$((i + 1))
        done
        if [ "$rows" -lt "$n" ]; then
            printf '%s\033[2m   %s · %d/%d\033[0m\n' "$INDENT" "$hint" "$sel" "$n"
        else
            printf '%s\033[2m   %s\033[0m\n' "$INDENT" "$hint"
        fi

        key=""
        IFS= read -rsn1 key || { sel=""; break; }
        case "$key" in
            "") break ;;
            "$esc")
                rest=""
                IFS= read -rsn2 -t 1 rest
                case "$rest" in
                    "[A"|"OA") [ "$sel" -gt 1 ] && sel=$((sel - 1)) || sel=$n ;;
                    "[B"|"OB") [ "$sel" -lt "$n" ] && sel=$((sel + 1)) || sel=1 ;;
                esac
                ;;
            k|K) [ "$sel" -gt 1 ] && sel=$((sel - 1)) || sel=$n ;;
            j|J) [ "$sel" -lt "$n" ] && sel=$((sel + 1)) || sel=1 ;;
            " ") break ;;
            [1-9])
                if [ "$n" -le 9 ] && [ "$key" -le "$n" ]; then
                    sel=$key
                    break
                fi
                ;;
        esac
    done

    # Свернуть меню в одну строку с итогом / Collapse the menu into one line
    printf '\033[%dA\r\033[J' $((rows + 2))
    if [ -n "$sel" ]; then
        local sep=":"
        case "$title" in *"?") sep="" ;; esac
        printf '%s%b%s%b %s%s %b%s%b\n' "$INDENT" "$FG_SUCCESS" "$CHECK" "$RESET" "$title" "$sep" \
            "$FG_ACCENT" "$(_ui_strip_num "$(_ui_item "$sel" "$@")")" "$RESET"
    fi
    _ui_tty_restore
    trap - INT TERM HUP
    eval "$saved_traps"
    [ -n "$sel" ] || return 1
    _UI_SEL=$sel
}

ui_choose() {
    local var="$1" title def="$3"
    title=$(printf '%s' "$2" | sed 's/[[:space:]:]*$//')
    shift 3
    _UI_SEL=""
    if ui_tty; then
        _ui_choose_tty "$title" "$def" "$@" || exit 1
    else
        _ui_choose_plain "$title" "$def" "$@"
    fi
    eval "$var=\$_UI_SEL"
}

# Разделитель / Separator
separator() {
    local text="$1"

    get_terminal_width() {
        local w
        w=$(tput cols 2>/dev/null)
        if [ -n "$w" ]; then
            echo "$w"
            return
        fi
        if [ -n "$COLUMNS" ]; then
            echo "$COLUMNS"
            return
        fi
        w=$(stty size 2>/dev/null | awk '{print $2}')
        if [ -n "$w" ]; then
            echo "$w"
            return
        fi
        echo 100
    }

    local width
    width=$(get_terminal_width)

    SEP_CHAR=${SEP_CHAR:-"o"}
    FG_ACCENT=${FG_ACCENT:-"\033[38;5;85m"}
    RESET=${RESET:-"\033[0m"}

    if [ -z "$text" ]; then
        local line
        line=$(printf "%${width}s" " " | tr ' ' "${SEP_CHAR}")
        echo -e "${FG_ACCENT}${line}${RESET}"
        return
    fi

    local clean_text
    clean_text=$(echo -n "$text" | sed 's/\x1b\[[0-9;]*m//g')

    local text_area=$((width / 2))
    local side_width=$((width / 4))

    if [ ${#clean_text} -le "$text_area" ]; then
        local padding_needed=$((text_area - ${#clean_text}))
        local left_padding=$((padding_needed / 2))
        local right_padding=$((padding_needed - left_padding))

        local side_part
        side_part=$(printf "%${side_width}s" " " | tr ' ' "${SEP_CHAR}")
        local left_text_pad
        left_text_pad=$(printf "%${left_padding}s" " ")
        local right_text_pad
        right_text_pad=$(printf "%${right_padding}s" " ")

        echo -e "${FG_ACCENT}${side_part}${RESET}${left_text_pad}${text}${right_text_pad}${FG_ACCENT}${side_part}${RESET}"
    else
        local remaining_text="$clean_text"
        local side_part
        side_part=$(printf "%${side_width}s" " " | tr ' ' "${SEP_CHAR}")

        while [ ${#remaining_text} -gt 0 ]; do
            local line_text=""
            local line_length=0

            if [ ${#remaining_text} -le "$text_area" ]; then
                line_text="$remaining_text"
                line_length=${#remaining_text}
                remaining_text=""
            else
                local cut_pos="$text_area"
                local i=$((text_area - 1))
                while [ $i -gt $((text_area / 2)) ]; do
                    local char
                    char=$(echo "$remaining_text" | cut -c$i)
                    if [ "$char" = " " ]; then
                        cut_pos=$i
                        break
                    fi
                    i=$((i - 1))
                done

                line_text=$(echo "$remaining_text" | cut -c1-"$cut_pos")
                line_length=${#line_text}
                remaining_text=$(echo "$remaining_text" | cut -c$((cut_pos + 1))-)
                remaining_text=$(echo "$remaining_text" | sed 's/^[[:space:]]*//')
            fi

            local padding_needed=$((text_area - line_length))
            local left_padding=$((padding_needed / 2))
            local right_padding=$((padding_needed - left_padding))

            local left_text_pad
            left_text_pad=$(printf "%${left_padding}s" " ")
            local right_text_pad
            right_text_pad=$(printf "%${right_padding}s" " ")

            echo -e "${FG_ACCENT}${side_part}${RESET}${left_text_pad}${line_text}${right_text_pad}${FG_ACCENT}${side_part}${RESET}"
        done
    fi
}

# Запуск шагов с разделителями / Run steps with separators
run_steps_with_separator() {
    for step in "$@"; do
        case "$step" in
            ::*)
                text="${step#::}"
                separator
                separator "$text"
                separator
                ;;
            *)
                $step
                separator
                printf "\n"
                ;;
        esac
    done
}
