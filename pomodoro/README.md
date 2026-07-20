# Pomodoro Timer

A Pomodoro timer plugin for Noctalia for productivity. Initially ported from the legacy v4 plugin [Pomodoro Timer](https://github.com/noctalia-dev/legacy-v4-plugins/tree/main/pomodoro).

## Features
- **Sessions**: Configurable sessions based on the standard format (work - short break - long break). Durations can be configured in the settings.
- **Cycles**: Configurable number of (work - short break) cycles before a long break.
- **Auto-start**: Optionally auto-start breaks and/or work sessions.
- **Bar Widget**: Shows status and remaining time on the bar widget when the panel is closed.
- **Notifications**: Toast notification when work/break finishes.

## TODO 
- Sound notification (currently the toast is shown silently)

## Plugin

| Field | Value |
| --- | --- |
| ID | `thepunkoff/pomodoro` |
| Entries | Bar widget: `widget`; panel: `panel`; service: `pomodoro` |

## Settings

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `workDuration` | `int` | `25` | Duration of each work session in minutes. |
| `shortBreakDuration` | `int` | `5` | Duration of short breaks in minutes. |
| `longBreakDuration` | `int` | `15` | Duration of long breaks in minutes. |
| `sessionsBeforeLongBreak` | `int` | `4` | Number of sessions before a long break. |
| `autoStartWork` | `bool` | `false` | Automatically start the work timer after a break. |
| `autoStartBreaks` | `bool` | `false` | Automatically start the break timer after a work session. |
