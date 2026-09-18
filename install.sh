#!/bin/bash
echo "Installing Quickshell Todo/Calendar Widget..."

mkdir -p ~/.config/quickshell-todo-widget
cp TodoWidget.qml calendar_sync.py ~/.config/quickshell-todo-widget/

mkdir -p ~/.local/state
touch ~/.local/state/todos.json
touch ~/.local/state/calendar_local.json

echo "Done! Run it with: qs -p ~/.config/quickshell-todo-widget/TodoWidget.qml"
