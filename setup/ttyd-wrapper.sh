#!/bin/bash
# Start tmux session with claude or cursor (cursor runs "agent" binary)

[ -f /home/sclaw/.env ] && . /home/sclaw/.env
agent="${SAFECLAW_AGENT:-claude}"
if [ "$agent" = "cursor" ]; then
    cmd="cursor"
else
    cmd="claude --dangerously-skip-permissions"
fi

if tmux has-session -t main 2>/dev/null; then
    exec tmux attach -t main
else
    tmux -f /dev/null new -d -s main
    tmux set -t main status off
    tmux set -t main mouse on
    tmux send-keys -t main "$cmd" Enter
    exec tmux attach -t main
fi
