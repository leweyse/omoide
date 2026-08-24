# Omoide

思い出 (*omoide*) is Japanese for a memory you keep.

https://github.com/user-attachments/assets/6699df68-81dc-43ea-8182-eaad28a516b2

More in [assets/](assets): the library, the capture menu, agent settings.

The idea is Nothing's, from
[Essential Space](https://nothing.community/d/44332-essential-space-everything-it-can-do)
on their phones. I wanted it on my computer, which is where I actually work, and
Omarchy's plugin system is what made that possible. Grab a screenshot, type a
note, or dictate one. An agent turns it into a memory with a title, a summary,
key facts, dates and to-dos.

Everything runs on your machine. No account, no server, nothing syncing. Your
memories are a SQLite file and a folder of images in your home directory. The
only thing that ever leaves is what you hand to a cloud agent, and nothing at
all if you run a local one.

## Capturing

- **Left-click** the bar icon runs the default action.
- **Middle-click** opens the library.
- **Right-click** opens the full menu: screenshot, quick note, voice note, the
  library and agent settings. Picking a capture mode there sets what left-click
  does from then on.

```text
screenshot ──▶ pick a region ──▶ overlay opens with the shot, note optional
note ────────▶ overlay opens empty, text required
voice ───────▶ overlay opens already listening, transcript lands editable
```

Enter saves. Esc discards the draft and its image. The button at the end of the
note field starts dictation in any mode, if Voxtype is installed.

## Browsing

One dialog, three views.

**For you** is today: a count of events and open tasks, then both lists.

**Library** is every capture, newest first, in a masonry grid. Agent tags filter
it. Search matches titles, notes, list items and OCR'd text, by prefix.

**Tasks** has three tabs, Upcoming, Past and Completed. Space ticks a row or
accepts a suggestion.

Ctrl 1 to 3 switch views, `/` searches, `?` lists every shortcut, Esc steps
back.

## What a memory holds

A memory is an ordered list of typed blocks, and which blocks appear depends on
what you captured. An article gives you a source, a summary and key points. A
screenshot of a design board gives you an image and a list of names, nothing
more.

## Tasks, events and reminders

Reminders are `systemd-run` timers, rebuilt from the database at startup so they
survive a reboot.

Anything the agent inferred rather than being told arrives as a suggestion, a
bullet with a `+` and no timer until you accept it.

## Install

```bash
omarchy plugin add https://github.com/leweyse/omoide.git --enable
```

It asks which bar section to put the icon in. Screenshots need `grim` and
`slurp`, OCR needs `tesseract`, dictation needs `voxtype`
(`omarchy-voxtype-install`).

To remove it, `omarchy plugin remove leweyse.omoide`. Your memories stay on
disk. Run `bin/omoide uninstall --purge` first if you want them gone with it.

For a keybinding, in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + <YOUR_CHOICE>", "Omoide capture",
       "omarchy-shell -q omoide capture screenshot")
```

## Choosing an agent

Presets cover claude, codex, opencode, gemini, ollama and aichat. `custom` takes
any command that reads the prompt on stdin and prints the answer on stdout.

Screenshots reach the agent as OCR text by default, so the image itself stays
here. "What the agent sees from a screenshot", in agent settings, switches that
to the screenshot itself, which reads charts and dense pages far better. Only
claude, codex, gemini and opencode take images, and the card says so for the
rest.

With no agent you still get the capture, your note, search over OCR'd text, and
a reminder from an explicit "remind me to call the vet tomorrow at 3pm".

## Where things live

```text
~/.config/omoide/config.json     the agent you chose
~/.local/share/omoide/           memories.db and blobs/, your captures
~/.local/state/omoide/           derived cache, rebuildable
```

## TODO list

**Voice dictation.** Voxtype does the transcription and the wiring is in, but I
have not put real use behind it. Next thing I want to fix.

**Export memories.** I still capture things on my Nothing phone and I want the
two halves to meet without a cloud account in between. The phone end is the part
I have not solved.

**Calendar integration.** Several providers, ideally, though it is low on my
list.

**Clipboard capture.** It already shows in the menu, disabled.
