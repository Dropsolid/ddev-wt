# ddev-worktree: wt — switch between git worktrees
# Install with: ddev wt-shell-install
# Usage: wt [partial-name | number | main | ls]

function wt --description 'Switch between git worktrees'
    # Collect all worktrees
    set -l worktrees (git worktree list --porcelain 2>/dev/null \
        | grep '^worktree ' | string replace 'worktree ' '')

    if test -z "$worktrees"
        echo "Not in a git repository" >&2; return 1
    end

    # ── wt ls / wt list ────────────────────────────────────────────────────────
    if test "$argv[1]" = ls -o "$argv[1]" = list
        set -l i 1
        for wt_path in $worktrees
            set -l name   (basename $wt_path)
            set -l branch (git -C $wt_path branch --show-current 2>/dev/null; or echo 'detached')
            set -l flags  ""
            test -d "$wt_path/.git" && set flags "$flags ✦"
            test "$wt_path" = "$PWD" && set flags "$flags ◀"
            printf "%2d) %-36s %s%s\n" $i $name $branch $flags
            set i (math $i + 1)
        end
        return 0
    end

    # ── wt (no args) — interactive picker ─────────────────────────────────────
    if test -z "$argv"
        if command -q fzf
            # Hidden first field = path, so selection maps back unambiguously
            # even if two worktrees share a display name (same as wt.bash).
            set -l items
            for wt_path in $worktrees
                set -l name   (basename $wt_path)
                set -l branch (git -C $wt_path branch --show-current 2>/dev/null; or echo 'detached')
                set -l flag   (test -d "$wt_path/.git" && echo " ✦" || echo "")
                set -a items (printf "%s\t%-36s %s%s" $wt_path $name $branch $flag)
            end
            set -l selected (printf '%s\n' $items | fzf \
                --height=~50% --min-height=6 --reverse \
                --prompt='  worktree > ' \
                --pointer='▶' \
                --no-info \
                --delimiter='\t' --with-nth=2..)
            if test -n "$selected"
                set -l target (string split -m1 \t -- $selected)[1]
                if test -n "$target" -a -d "$target"
                    cd $target
                    _wt_prompt (basename $target) \
                        (git -C $target branch --show-current 2>/dev/null)
                end
            end
        else
            # Fallback: numbered list
            wt ls
            echo ""
            read -P "  Switch to number (Enter to cancel): " choice
            if test -n "$choice" && string match -qr '^[0-9]+$' $choice
                and test $choice -ge 1 -a $choice -le (count $worktrees)
                cd $worktrees[$choice]
                _wt_prompt (basename $worktrees[$choice]) \
                    (git -C $worktrees[$choice] branch --show-current 2>/dev/null)
            end
        end
        return 0
    end

    # ── wt <query> — match by partial name, branch, or number ─────────────────
    set -l query $argv[1]

    # Number shortcut
    if string match -qr '^[0-9]+$' $query
        and test $query -ge 1 -a $query -le (count $worktrees)
        cd $worktrees[$query]
        _wt_prompt (basename $worktrees[$query]) \
            (git -C $worktrees[$query] branch --show-current 2>/dev/null)
        return 0
    end

    # "main" / "." shortcut — jump to main checkout
    if contains -- $query main . master
        for wt_path in $worktrees
            if test -d "$wt_path/.git"
                cd $wt_path
                _wt_prompt "(main)" (git -C $wt_path branch --show-current 2>/dev/null)
                return 0
            end
        end
    end

    # Partial match on dir name or branch name
    set -l matches
    for wt_path in $worktrees
        set -l name   (basename $wt_path)
        set -l branch (git -C $wt_path branch --show-current 2>/dev/null; or echo '')
        if string match -q "*$query*" $name; or string match -q "*$query*" $branch
            set matches $matches $wt_path
        end
    end

    switch (count $matches)
        case 1
            cd $matches[1]
            _wt_prompt (basename $matches[1]) (git -C $matches[1] branch --show-current 2>/dev/null)
        case 0
            echo "No worktree matching '$query'" >&2
            wt ls; return 1
        case '*'
            echo "Multiple matches for '$query' — be more specific:" >&2
            for m in $matches; echo "  $(basename $m)" >&2; end
            return 1
    end
end

function _wt_prompt --argument-names name branch
    set_color green; echo -n "→ "; set_color normal
    echo -n $name
    if test -n "$branch"
        set_color brblack; echo -n "  ($branch)"; set_color normal
    end
    echo ""
end
