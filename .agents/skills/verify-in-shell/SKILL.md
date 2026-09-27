---
name: verify-in-shell
description: See a QML or CLI change running in the live Omarchy shell. Covers when a plugin reload is enough and when only a shell restart picks a change up, confirming which CLI build is loaded, finding the Space window and other surfaces as Wayland layers, opening a page over IPC, driving the keyboard with wtype, reading the shell's log, measuring a screenshot, and faking a smaller screen. Use before restarting anything and before claiming a UI change works. Do not use for CLI behavior that dev/parity can prove, which needs no shell at all.
---

# Verify in the shell

The shell being restarted is the user's live desktop. Form a hypothesis, check it in one or two cycles, and batch visual changes into one restart. A loop of edit, restart, screenshot, measure is slower than the user's own feedback. It also produces false signals when their screenshot shows a build already replaced, so before acting on one, check which build it shows by comparing a number you can measure in the image.

## 1. Make the change load

| Edited | Picks up with |
| ------ | ------------- |
| `BarWidget.qml`, `dialogs/ActionMenu.qml`, other files a widget loads fresh | the plugin watcher, a second or so after saving |
| `Service.qml`, anything under `components/` or `common/`, anything a kept surface loaded | `omarchy-restart-shell` only; the watcher logs "reloading" and keeps rendering the old code |
| `cli/`, `sql/`, `prompts/`, `manifest.json` | a shell restart, which rebuilds the CLI because the source id changed |

The trap is a batch touching both rows: the widget reloads, the component does not, and the result looks half-applied. When in doubt, restart; it takes about ten seconds to come back.

Confirm the CLI the shell is using with `~/.cache/omoide/bin/omoide --version`. With uncommitted changes under `cli/`, its `source` is `local`, because a dirty tree rebuilds on every load.

## 2. Read the log

The shell writes a log per instance under `/run/user/$(id -u)/quickshell/by-id/`. Read the newest with `quickshell log -t 50 <file>`, or read the running shell's with `qs -p /usr/share/omarchy/shell log`; a bare `qs log` fails with "no default config". A plugin that fails to load logs `Plugin widget leweyse.omoide failed:` and shows nothing, and a failed CLI build also sends a critical notification.

`console.log` from a temporary `Timer` is the only way to read real geometry. Remove it before handing off.

## 3. Find and open surfaces

Every surface is a layer, so it never appears in `hyprctl clients`. Finding nothing there is not a failure to open.

- Present: `hyprctl layers | grep 'namespace: omoide'`. The compose overlay, settings and help are `omoide-compose`, `omoide-settings` and `omoide-help`.
- Open a page: `omarchy-shell omoide openSpace '{"section":"library"}'`, or `'{"id":"<memory id>"}'` for a memory's detail page.
- The IPC call answers `ok` whether or not anything opened, so it is not evidence.

No IPC opens the item or block editor. Both are children of the Space window, though, so opening the window instantiates them, and a structural error in anything they use appears in the log at that point. That is a cheap smoke test for a shared component.

## 4. Drive it

The Space window takes exclusive keyboard focus, so `wtype -k Down`, `wtype -k Return` and `wtype -k Escape` reach it. Opening at a section puts focus in the rail, not the page: from there Down moves the rail cursor. Enter the page first (open at `foryou`, then Down and Return) or the keys measure nothing.

## 5. Measure

Take the screen with `grim` and scan the pixels for the colors in question with PIL, rather than eyeballing a crop. A present one-pixel border and a missing one look identical once scaled.

To reproduce a small screen without a second monitor, copy `surfaces/SpaceWindow.qml` aside, lower the `Style.space(1000)` literal that sets the dialog width, restart, measure, then restore the copy and `git diff` the file to prove the override is gone.

## 6. Report

Say what was run: restart or reload, which surfaces were opened, what the log showed, what was measured. A change that could not be driven, such as an editor dialog with no IPC, is reported as not verified in the shell, not as working.
