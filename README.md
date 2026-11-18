# WinSwitch

A small **Alt+Tab window switcher** for macOS, like in Windows or KDE.

Hold **⌘**, press **Tab** to move through your windows, release **⌘** to switch.
On a PC keyboard, ⌘ is the **Alt** key.

- Shows windows, not apps (macOS ⌘Tab shows apps).
- Shows the title and icon only. No screenshots, so no Screen Recording permission and no purple dot.
- While WinSwitch runs, the macOS ⌘Tab app switcher is off. It comes back when you quit WinSwitch.

## Install

```sh
make install    # build, sign, copy to /Applications, start
```

You need Xcode and an "Apple Development" certificate. To use another one:
`make install SIGN_ID="..."`.

On the first start, macOS asks for **Accessibility** permission. WinSwitch needs it to read keys and
move windows. Turn it on in System Settings → Privacy & Security → Accessibility. You don't need to
restart the app.

## Keys

Hold ⌘ all the time:

| Key | Action |
|---|---|
| Tab | Open the list, or go to the next window |
| ⇧Tab | Previous window |
| Arrows | Move in the list |
| Release ⌘ or ↩ | Switch to the selected window |
| Esc | Close the list |

A short ⌘Tab switches to the last window and does not show the list.
When the list is open, other keys do nothing.

## Start and stop

WinSwitch has no Dock icon. It has an icon in the menu bar (top right of the screen).

| To | Do |
|---|---|
| Start | Open WinSwitch from Applications, the Dock or Spotlight. Or run `open -a WinSwitch` |
| Stop | Menu bar icon → Quit WinSwitch. Or run `pkill -x WinSwitch` |
| Settings | Menu bar icon → Settings. Or open the app again while it runs |
| See logs | `/usr/bin/log stream --predicate 'subsystem == "local.winswitch"'` |

Use the full path `/usr/bin/log`: in zsh, `log` is a different command.

## Settings

- **Shortcut** (default ⌘Tab). Click the button and press new keys. The keys must include ⌘, ⌥ or ⌃.
  Esc cancels. If you use any shortcut other than ⌘Tab or ⌘`, the macOS ⌘Tab works as usual.
- **Only windows on current desktop** (default on). If off, the list also shows windows on other
  desktops. macOS only shows WinSwitch the windows of desktops you opened after WinSwitch started.
- **Start at login** (default on). You can also see it in System Settings → General → Login Items.

The settings are saved in `defaults read local.winswitch`.

## Development

```sh
make bundle     # build build/WinSwitch.app
make run        # run in the terminal and show logs
make clean
build/WinSwitch.app/Contents/MacOS/WinSwitch --list   # print the window list
```

When you start it from a terminal, macOS uses the terminal's permission, not WinSwitch's.

Files in `Sources/WinSwitch/`:

| File | What it does |
|---|---|
| `HotkeyTap.swift` | Reads keys from all apps, opens and moves the list, records new shortcuts |
| `Windows.swift` | Finds windows and switches to them |
| `SwitcherPanel.swift` | The list on the screen |
| `SystemHotkeys.swift` | Turns the macOS ⌘Tab off and on |
| `AppDelegate.swift`, `Settings.swift`, `SettingsView.swift` | Menu bar icon, settings |

## Uninstall

First turn off "Start at login" in Settings. Then:

```sh
make uninstall  # quit, remove the app, reset permission and settings
```

## Limitations

- Does not work when a password field is active. macOS blocks key reading there.
- Does not show minimized or hidden windows.
- A full-screen app is a separate desktop.
- If WinSwitch crashes, the macOS ⌘Tab stays off until you start WinSwitch again or log out.
- Uses two private macOS functions: `_AXUIElementGetWindow` and `CGSSetSymbolicHotKeyEnabled`.
  Other apps (AltTab, Hammerspoon, yabai) use them too, and they have worked for more than 10 years.
