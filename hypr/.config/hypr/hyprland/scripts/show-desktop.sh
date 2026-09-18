#!/bin/bash
# Show desktop toggle - moves all windows on current workspace to special:hidden and back

SPECIAL="hidden"
CURRENT=$(hyprctl activeworkspace -j | jq -r '.id')
HIDDEN_COUNT=$(hyprctl clients -j | jq "[.[] | select(.workspace.name == \"special:$SPECIAL\")] | length")

if [ "$HIDDEN_COUNT" -gt 0 ]; then
    # Windows are hidden, bring them back
    hyprctl clients -j | jq -r ".[] | select(.workspace.name == \"special:$SPECIAL\") | .address" | while read addr; do
        hyprctl dispatch movetoworkspacesilent "$CURRENT,address:$addr"
    done
else
    # Hide all windows on current workspace
    hyprctl clients -j | jq -r ".[] | select(.workspace.id == $CURRENT) | .address" | while read addr; do
        hyprctl dispatch movetoworkspacesilent "special:$SPECIAL,address:$addr"
    done
fi
