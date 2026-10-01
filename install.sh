#!/bin/bash
echo "Installing Quickshell Todo & Calendar Widget..."

mkdir -p ~/.config/quickshell-todo-widget
cp TodoWidget.qml calendar_sync.py ~/.config/quickshell-todo-widget/

mkdir -p ~/.local/state
touch ~/.local/state/todos.json
touch ~/.local/state/calendar_local.json

# Caelestia Hyprland autostart detection
if [ -d "$HOME/.config/caelestia" ]; then
    USER_LUA="$HOME/.config/caelestia/hypr-user.lua"
    if ! grep -q "quickshell-todo-widget" "$USER_LUA" 2>/dev/null; then
        cat << 'EOF' >> "$USER_LUA"

-- Caelestia Todo Widget Autostart (Vulkan backend for lowest memory footprint)
hl.on("hyprland.start", function()
    hl.exec_cmd("env QSG_RHI_BACKEND=vulkan qs -p " .. os.getenv("HOME") .. "/.config/quickshell-todo-widget/TodoWidget.qml -d")
end)
EOF
        echo "Added autostart to $USER_LUA"
    fi
fi

echo "Done! Run it with: env QSG_RHI_BACKEND=vulkan qs -p ~/.config/quickshell-todo-widget/TodoWidget.qml -d"
