# ddev-worktree: wt-ai — switch to a worktree and start a Claude Code session
# Install with: ddev wt-shell-install
# Usage: wt-ai [partial-name | number | main]
# Override AI tool: set -x WORKTREE_AI_CMD cursor

function wt-ai --description 'Switch to a worktree and start a Claude Code session'
    set -l ai (test -n "$WORKTREE_AI_CMD" && echo $WORKTREE_AI_CMD || echo claude)
    wt $argv; and $ai
end
