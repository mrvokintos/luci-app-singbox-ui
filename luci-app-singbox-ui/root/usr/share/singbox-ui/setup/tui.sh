#!/bin/sh
# Полноэкранное меню для busybox ash (без stty/tput/dialog).
# Full-screen menu for busybox ash (no stty/tput/dialog).
#
#   tui_enter / tui_leave        — отдельный экран терминала / alternate screen
#   tui_menu VAR SEL ITEM...     — список; в VAR номер пункта или 0 (назад/выход)
#                                  list; VAR gets the item number or 0 (back/quit)
# Пункт: "Текст" или "Текст<TAB>Значение"; "-" — разделитель, "#Текст" — строка
# без выбора. Item: "Label" or "Label<TAB>Value"; "-" is a separator, "#Text" is
# a plain line; neither can be selected.
# Заголовок и подсказка берутся из TUI_TITLE, TUI_SUBTITLE, TUI_HEADING, TUI_HINT.
# Клавиши: ↑/↓ j/k — ход, Enter/→/пробел — выбрать, q/Esc/← — назад.

TUI_ROWS=24
TUI_COLS=80
TUI_VALUE_COL=30
TUI_ACTIVE=0
_TUI_TAB=$(printf '\t')
_TUI_ESC=$(printf '\033')

# Размер терминала: LINES/COLUMNS или ответ на \033[18t / Terminal size
tui_size() {
    local resp rows cols
    if [ -n "$LINES" ] && [ -n "$COLUMNS" ]; then
        TUI_ROWS=$LINES TUI_COLS=$COLUMNS
        return 0
    fi
    printf '\033[18t'
    resp=""
    IFS= read -rs -d t -t 1 resp
    resp=${resp#*\[8;}
    rows=${resp%%;*}
    cols=${resp#*;}
    case "$rows$cols" in
        ''|*[!0-9]*) return 0 ;;
    esac
    [ "$rows" -ge 10 ] && TUI_ROWS=$rows
    [ "$cols" -ge 40 ] && TUI_COLS=$cols
    return 0
}

_tui_restore_screen() {
    printf '\033[0m\033[?7h\033[?25h\033[?1049l'
}

tui_enter() {
    [ "$TUI_ACTIVE" = 1 ] && return 0
    TUI_ACTIVE=1
    printf '\033[?1049h\033[?25l\033[?7l\033[H\033[2J'
    tui_size
}

tui_leave() {
    [ "$TUI_ACTIVE" = 1 ] || return 0
    TUI_ACTIVE=0
    _tui_restore_screen
}

_tui_item() {
    eval "printf '%s' \"\${$(($1 + 1))}\""
}

_tui_selectable() {
    case "$(_tui_item "$@")" in
        -|"#"*) return 1 ;;
    esac
    return 0
}

# Шаг к следующему выбираемому пункту / Step to the next selectable item
_tui_step() {
    local sel="$1" dir="$2" n="$3" i=0
    shift 3
    while [ "$i" -lt "$n" ]; do
        sel=$((sel + dir))
        [ "$sel" -lt 1 ] && sel=$n
        [ "$sel" -gt "$n" ] && sel=1
        _tui_selectable "$sel" "$@" && break
        i=$((i + 1))
    done
    echo "$sel"
}

_tui_draw() {
    local sel="$1" off="$2" rows="$3" n="$4" i end item label value line
    shift 4
    printf '\033[H'
    printf '\033[1;97;44m %s\033[K\033[0m\n' "$TUI_TITLE"
    printf '\033[2m %s\033[0m\033[K\n' "$TUI_SUBTITLE"
    printf '\033[K\n'
    if [ -n "$TUI_HEADING" ]; then
        printf ' \033[1m%s\033[0m\033[K\n\033[K\n' "$TUI_HEADING"
    fi
    i=$off
    end=$((off + rows - 1))
    [ "$end" -gt "$n" ] && end=$n
    while [ "$i" -le "$end" ]; do
        item=$(_tui_item "$i" "$@")
        # Стереть строку целиком: значение ставится прыжком в колонку, и промежуток
        # иначе хранит текст прошлого экрана. Erase the whole line: the value is
        # placed by jumping to a column, so the gap would keep the previous screen.
        printf '\033[2K'
        if [ "$item" = "-" ]; then
            printf '   \033[2m%s\033[0m\033[K\n' "────────────────────────"
        elif [ "${item#"#"}" != "$item" ]; then
            printf '   %s\033[K\n' "${item#"#"}"
        else
            label=${item%%"$_TUI_TAB"*}
            value=""
            case "$item" in *"$_TUI_TAB"*) value=${item#*"$_TUI_TAB"} ;; esac
            if [ "$i" = "$sel" ]; then
                line=$(printf '\033[1;30;46m ❯ %s ' "$label")
            else
                line=$(printf '   %s ' "$label")
            fi
            if [ -n "$value" ]; then
                printf '%s\033[0m\033[%dG\033[36m%s\033[0m\033[K\n' "$line" "$TUI_VALUE_COL" "$value"
            else
                printf '%s\033[0m\033[K\n' "$line"
            fi
        fi
        i=$((i + 1))
    done
    printf '\033[J'
    if [ "$n" -gt "$rows" ]; then
        printf '\033[%d;1H\033[2m %s · %d/%d\033[0m\033[K' "$TUI_ROWS" "$TUI_HINT" "$sel" "$n"
    else
        printf '\033[%d;1H\033[2m %s\033[0m\033[K' "$TUI_ROWS" "$TUI_HINT"
    fi
}

# tui_menu VAR SEL ITEM...
tui_menu() {
    local _tm_var="$1" _tm_sel="${2:-1}" _tm_n _tm_rows _tm_off _tm_key _tm_rest _tm_top _tm_i
    shift 2
    _tm_n=$#
    _tm_top=4
    [ -n "$TUI_HEADING" ] && _tm_top=6
    _tm_rows=$((TUI_ROWS - _tm_top - 1))
    [ "$_tm_rows" -lt 3 ] && _tm_rows=3
    [ "$_tm_sel" -ge 1 ] 2>/dev/null && [ "$_tm_sel" -le "$_tm_n" ] || _tm_sel=1
    _tui_selectable "$_tm_sel" "$@" || _tm_sel=$(_tui_step "$_tm_sel" 1 "$_tm_n" "$@")
    _tm_off=1
    while true; do
        [ "$_tm_sel" -lt "$_tm_off" ] && _tm_off=$_tm_sel
        [ "$_tm_sel" -ge $((_tm_off + _tm_rows)) ] && _tm_off=$((_tm_sel - _tm_rows + 1))
        _tui_draw "$_tm_sel" "$_tm_off" "$_tm_rows" "$_tm_n" "$@"
        _tm_key=""
        IFS= read -rsn1 _tm_key || { _tm_sel=0; break; }
        case "$_tm_key" in
            ""|" ") break ;;
            "$_TUI_ESC")
                _tm_rest=""
                IFS= read -rsn2 -t 1 _tm_rest
                case "$_tm_rest" in
                    "[A"|"OA") _tm_sel=$(_tui_step "$_tm_sel" -1 "$_tm_n" "$@") ;;
                    "[B"|"OB") _tm_sel=$(_tui_step "$_tm_sel" 1 "$_tm_n" "$@") ;;
                    "[C"|"OC") break ;;
                    "[D"|"OD"|"") _tm_sel=0; break ;;
                    "[5"|"[6")
                        IFS= read -rsn1 -t 1 _tm_key
                        _tm_i=0
                        while [ "$_tm_i" -lt "$_tm_rows" ]; do
                            if [ "$_tm_rest" = "[5" ]; then
                                _tm_sel=$(_tui_step "$_tm_sel" -1 "$_tm_n" "$@")
                            else
                                _tm_sel=$(_tui_step "$_tm_sel" 1 "$_tm_n" "$@")
                            fi
                            _tm_i=$((_tm_i + 1))
                        done
                        ;;
                esac
                ;;
            k|K) _tm_sel=$(_tui_step "$_tm_sel" -1 "$_tm_n" "$@") ;;
            j|J) _tm_sel=$(_tui_step "$_tm_sel" 1 "$_tm_n" "$@") ;;
            q|Q) _tm_sel=0; break ;;
        esac
    done
    eval "$_tm_var=\$_tm_sel"
}

# tui_choose VAR HEADING CURRENT ITEM... — подменю выбора значения
# Submenu to pick a value: the current item is marked with ●.
# VAR gets the item number, or stays unchanged on back.
tui_choose() {
    local _tc_var="$1" _tc_heading="$2" _tc_current="$3" _tc_i=1 _tc_item _tc_r
    shift 3
    set -- "$@"
    local _tc_marked=""
    for _tc_item in "$@"; do
        if [ "$_tc_i" = "$_tc_current" ]; then
            _tc_marked="$_tc_marked ● $_tc_item$_TUI_TAB"
        else
            _tc_marked="$_tc_marked   $_tc_item$_TUI_TAB"
        fi
        _tc_i=$((_tc_i + 1))
    done
    # Пересобрать список с отметками / Rebuild the list with marks
    local IFS="$_TUI_TAB"
    # shellcheck disable=SC2086
    set -- $_tc_marked
    unset IFS
    local _tc_sh="$TUI_HEADING" _tc_shint="$TUI_HINT"
    TUI_HEADING="$_tc_heading"
    TUI_HINT="${TUI_HINT_SUB:-$TUI_HINT}"
    tui_menu _tc_r "$_tc_current" "$@"
    TUI_HEADING="$_tc_sh"
    TUI_HINT="$_tc_shint"
    [ "$_tc_r" -gt 0 ] && eval "$_tc_var=\$_tc_r"
    return 0
}
