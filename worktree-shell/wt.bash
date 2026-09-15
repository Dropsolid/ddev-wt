# ddev-wt: wt — switch between git worktrees
# Install with: ddev wt-shell-install
# Usage: wt [partial-name | number | main | ls]
#
# Portable across bash 3.2 (macOS stock), bash 4+ (Linux), and zsh (macOS default).
# Deliberately avoids: mapfile/readarray (bash 4+), ${!arr[@]} (not in zsh),
# fixed array index bases (zsh is 1-based, bash 0-based — we iterate with a counter),
# `read -p` / `echo -e` (differ between bash and zsh — we use printf + read -r), and
# the variable name `path` (in zsh it is a special array tied to $PATH — using it
# would blank PATH inside the function and break grep/sed/etc).

wt() {
    local _green=$'\033[32m' _gray=$'\033[90m' _reset=$'\033[0m'
    local worktrees line query name branch flag i count wt_path matches selected target items tab choice

    # Collect worktree paths without mapfile (bash 3.2 / zsh safe)
    worktrees=()
    while IFS= read -r line; do
        [ -n "$line" ] && worktrees+=("$line")
    done < <(git worktree list --porcelain 2>/dev/null | grep '^worktree ' | sed 's/^worktree //')

    count=${#worktrees[@]}
    if [ "$count" -eq 0 ]; then
        echo "Not in a git repository" >&2
        return 1
    fi

    # ── wt ls / wt list ──────────────────────────────────────────────────────
    if [ "${1:-}" = ls ] || [ "${1:-}" = list ]; then
        i=0
        for wt_path in "${worktrees[@]}"; do
            i=$((i + 1))
            name=$(basename "$wt_path")
            branch=$(git -C "$wt_path" branch --show-current 2>/dev/null || echo detached)
            flag=""
            [ -d "$wt_path/.git" ] && flag="$flag ✦"
            [ "$wt_path" = "$PWD" ] && flag="$flag ◀"
            printf '%2d) %-36s %s%s\n' "$i" "$name" "$branch" "$flag"
        done
        return 0
    fi

    # ── wt (no args) — interactive picker ──────────────────────────────────────
    if [ -z "${1:-}" ]; then
        if command -v fzf >/dev/null 2>&1; then
            tab=$(printf '\t')
            items=""
            for wt_path in "${worktrees[@]}"; do
                name=$(basename "$wt_path")
                branch=$(git -C "$wt_path" branch --show-current 2>/dev/null || echo detached)
                flag=""
                [ -d "$wt_path/.git" ] && flag=" ✦"
                # Hidden first field = path, so selection maps back unambiguously
                # even if two worktrees share a display name.
                items="${items}${wt_path}${tab}$(printf '%-36s %s%s' "$name" "$branch" "$flag")
"
            done
            selected=$(printf '%s' "$items" | fzf --height=~50% --min-height=6 --reverse \
                --prompt='  worktree > ' --pointer='▶' --no-info \
                --delimiter='\t' --with-nth=2..)
            if [ -n "$selected" ]; then
                target=${selected%%${tab}*}
                if [ -d "$target" ]; then
                    cd "$target" || return 1
                    printf '%s→%s %s %s(%s)%s\n' "$_green" "$_reset" \
                        "$(basename "$target")" "$_gray" \
                        "$(git branch --show-current 2>/dev/null)" "$_reset"
                fi
            fi
        else
            wt ls
            echo ""
            printf '  Switch to number (Enter to cancel): '
            read -r choice
            case "$choice" in
                ''|*[!0-9]*) : ;;  # empty or non-numeric → cancel
                *)
                    if [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
                        i=0
                        for wt_path in "${worktrees[@]}"; do
                            i=$((i + 1))
                            if [ "$i" -eq "$choice" ]; then
                                cd "$wt_path" || return 1
                                printf '%s→%s %s\n' "$_green" "$_reset" "$(basename "$wt_path")"
                                break
                            fi
                        done
                    fi
                    ;;
            esac
        fi
        return 0
    fi

    query="$1"

    # ── number shortcut (out-of-range falls through to partial match) ──────────
    case "$query" in
        ''|*[!0-9]*) : ;;  # not a pure number — fall through to matching
        *)
            if [ "$query" -ge 1 ] && [ "$query" -le "$count" ]; then
                i=0
                for wt_path in "${worktrees[@]}"; do
                    i=$((i + 1))
                    if [ "$i" -eq "$query" ]; then
                        cd "$wt_path" || return 1
                        printf '%s→%s %s %s(%s)%s\n' "$_green" "$_reset" \
                            "$(basename "$wt_path")" "$_gray" \
                            "$(git branch --show-current 2>/dev/null)" "$_reset"
                        return 0
                    fi
                done
            fi
            # Out of range (e.g. `wt 57` when there's no 57th worktree) → treat as
            # a partial match below, so it can still match feature-PROJ-57.
            ;;
    esac

    # ── main / . / master shortcut ─────────────────────────────────────────────
    if [ "$query" = main ] || [ "$query" = . ] || [ "$query" = master ]; then
        for wt_path in "${worktrees[@]}"; do
            if [ -d "$wt_path/.git" ]; then
                cd "$wt_path" || return 1
                printf '%s→%s (main) %s\n' "$_green" "$_reset" "$(basename "$wt_path")"
                return 0
            fi
        done
    fi

    # ── partial match on directory name or branch name ─────────────────────────
    matches=()
    for wt_path in "${worktrees[@]}"; do
        name=$(basename "$wt_path")
        branch=$(git -C "$wt_path" branch --show-current 2>/dev/null || echo '')
        case "$name" in
            *"$query"*) matches+=("$wt_path"); continue ;;
        esac
        case "$branch" in
            *"$query"*) matches+=("$wt_path") ;;
        esac
    done

    case ${#matches[@]} in
        1)
            for wt_path in "${matches[@]}"; do
                cd "$wt_path" || return 1
            done
            printf '%s→%s %s %s(%s)%s\n' "$_green" "$_reset" \
                "$(basename "$PWD")" "$_gray" \
                "$(git branch --show-current 2>/dev/null)" "$_reset"
            ;;
        0)
            echo "No worktree matching '$query'" >&2
            wt ls
            return 1
            ;;
        *)
            echo "Multiple matches for '$query' — be more specific:" >&2
            for wt_path in "${matches[@]}"; do echo "  $(basename "$wt_path")" >&2; done
            return 1
            ;;
    esac
}

# wt-ai: switch to a worktree and launch Claude Code (or $WORKTREE_AI_CMD)
wt-ai() {
    local ai="${WORKTREE_AI_CMD:-claude}"
    wt "$@" && "$ai"
}
