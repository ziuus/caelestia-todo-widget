# Quickshell Premium Todo & Calendar Widget

A highly polished, fully animated, desktop-embedded Wayland widget for tracking tasks and calendar events seamlessly.

## Features
- **Premium Animations**: Fluid entry/exit transitions, magnetic hover scaling, and spinning checkbox completions.
- **Wayland Native**: Built with [Quickshell](https://outfoxxed.me/quickshell) to natively anchor to your desktop layer behind your active windows (or above them if configured).
- **Dual Views**:
  - **Tasks**: Track 'Today' and 'Daily' habits seamlessly.
  - **Calendar**: Syncs local events alongside remote `.ics` (Google Calendar) links.
- **Catppuccin Styled**: Deeply integrated styling out of the box.

## Requirements
- [Quickshell 0.3+](https://github.com/outfoxxed/quickshell)
- Python 3
- `Material Symbols Rounded` font installed on your system.

## Installation
```bash
git clone https://github.com/YOUR_USERNAME/quickshell-todo-widget.git
cd quickshell-todo-widget
./install.sh
```

## Usage
Run it via the quickshell CLI:
```bash
qs -p ~/.config/quickshell-todo-widget/TodoWidget.qml -d
```
You can add this command to your `hyprland.conf` or window manager autostart file to launch it on boot.

## Configuration
To sync a remote calendar, create `~/.local/state/calendar_config.json`:
```json
{
  "ics_url": "https://calendar.google.com/calendar/ical/..."
}
```
