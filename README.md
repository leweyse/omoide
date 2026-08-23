# Omoide

Grab a screenshot, type a note, or dictate one. An agent turns it into a
structured memory with a title, a summary, key facts, dates and to-dos. Browse
it all later in one dialog with search, filters and collections.

思い出 (*omoide*) is Japanese for a memory you keep, the kind you go back to.

The idea comes from Nothing's Essential Space, which does this from a dedicated
hardware key on their recent phones. Credit to them for the concept. This is a
rebuild for Omarchy, driven from a bar icon and a keybind instead.

## Capturing

Left-click the bar icon, or press SUPER + CTRL + M.

```
screenshot ──▶ region pick ──▶ note field opens, note optional
note ────────▶ empty field, text required
voice ───────▶ dictation starts, transcript lands in the field, editable
                     │
              submit │  the overlay closes at once
                     ▼
              the agent runs detached, the bar icon animates,
              a notification arrives when it finishes
```

Screenshot is the default action. Set it to note or voice instead from the
right-click menu, which also holds the other modes, the library, and settings.
Middle-click opens the library.

Submitting needs at least one of a screenshot, some text, or a transcript. An
empty capture never commits. Esc throws the draft away along with its image.

The agent never sits between you and a saved capture. The memory row lands
before enrichment starts, so a model that fails, times out, or gets interrupted
by a shell restart still leaves you the screenshot, the note, and any date the
built-in grammar could parse out of phrases like "tomorrow at 3pm" or "in 2h".

## Browsing

One dialog, three views.

**For you** is a digest. Two count queries fill a fixed sentence, so the
headline says the same thing every time and costs nothing to produce. Below it
sit upcoming events and open tasks.

**Library** is the grid of everything, newest first, laid out by thumbnail
height rather than in even rows. Tags the agent assigned become filter chips
along the top. The optional search box runs full-text search over titles,
notes, list items and OCR'd text, and it matches prefixes, so "maxim" finds
"maximalism".

**To-dos** is the archive, grouped into Upcoming, Past, Anytime and Completed.
Grouping reads the item's own due date and completion state, never whether its
alarm already fired. Otherwise a to-do would disappear from the list the moment
its notification arrived, which is exactly when you need it most.

Clicking a memory opens its block document, with related captures and
collections underneath and a dropdown beside the title to delete it.

## What a memory holds

Not a fixed record. A memory is an ordered list of typed blocks, and which
blocks appear depends on what you captured. An article gives you a source, a
summary and a list of key points. An event listing gives you a date, a
location, and something to attend. A screenshot of a design board gives you an
image and a list of names, nothing more.

Headings come from two different owners. A list heading has to fit its content,
so the agent writes it, which is where "Key interior design trends for 2026"
comes from. The words "Summary", "Event date" and "To-dos" belong to the
renderer and are fixed, because a model rewording them per capture makes every
page read differently.

The plugin stores block types it does not recognise, skips them when rendering,
and never rewrites them. A database written by a newer version opens in an
older one with some cards missing instead of losing rows.

## To-dos, events and reminders

To-dos and events are rows in `items`. Reminders are separate rows pointing at
them.

A to-do can have a reminder, and a reminder can belong to something that is not
a to-do. An event wants "30 minutes before" just as much, and one item can
carry several alarms at once. Putting the alarm on the item as a column would
have turned both of those into painful migrations later. What is here instead
is the iCalendar shape, VTODO and VEVENT with VALARM children, so syncing to
Google or CalDAV becomes a mapping job rather than a schema rewrite.

Each reminder row gets one transient `systemd-run` timer. The shell rebuilds
them from the database at startup, so they survive a reboot. Omarchy's built-in
reminders take relative minutes and keep nothing on disk, so a reboot loses
them. That gap is most of why this plugin exists.

Anything the agent inferred rather than being asked for arrives as a
suggestion, drawn as a bullet with a `+` instead of a tickable circle, with no
timer until you accept it. Only what you asked for outright gets scheduled.
Both the prompt and the CLI default to suggesting when the signal is missing,
so an ambiguous response schedules nothing.

## Choosing an agent

Enrichment stays off until you configure it. The plugin never guesses and never
runs whichever CLI happens to be on your PATH.

```bash
bin/omoide setup-ai --provider claude
bin/omoide setup-ai --provider ollama --model llama3.2
bin/omoide setup-ai --provider custom --command 'my-llm --json'
bin/omoide setup-ai --disable
```

The settings dialog does the same thing, from the right-click menu.

Presets cover claude, codex, opencode, gemini, ollama and aichat. Each runs
headless, reads the prompt on stdin, and prints its answer on stdout. `custom`
takes any argv that does the same. Providers you have not installed show up in
the dialog dimmed with the reason rather than hidden.

`--vision ocr` is the default. Tesseract pulls text out of the screenshot and
only that text goes to the agent, which works everywhere including with a local
model, and the image never leaves the machine. `--vision image` sends the file
instead and reads charts and dense pages far better. Only claude, codex, gemini
and a custom command can use it. Anything else falls back to OCR, so the
dialog dims that choice and names the agent that cannot take it.

With no agent at all you still get the screenshot, your note, full-text search
across OCR'd text, collections, and a reminder from an explicit "remind me to
call the vet tomorrow at 3pm".

## Install

```bash
bin/omoide install
bin/omoide install --accel "SUPER + ALT + M"
bin/omoide install --no-keybind
bin/omoide uninstall
bin/omoide uninstall --purge
```

`install` enables the plugin, puts the widget in the bar's right section, and
binds SUPER + CTRL + M. Run it twice and you still have one installation. If a
later step fails it reverses the ones that already succeeded.

Everything outside this directory changes through Omarchy's own commands,
`omarchy plugin enable` and `omarchy bar put`, so it comes undone the same way.
One thing has no Omarchy command behind it and gets written directly.

The keybind goes into a marked block in `~/.config/hypr/bindings.lua`.
`install` replaces that block instead of appending to it, refuses and tells you
if the chord is already bound, and rolls the write back if `hyprctl
configerrors` returns anything. A refused keybind is not a failed install,
since the bar icon is the main entry point anyway.

That is now the only one. `setup-ai` used to be the second, writing the agent
block into `shell.json`; it writes `~/.config/omoide/config.json` instead.

The keybind write leaves no `.bak` file anywhere. Its rollback copy lives in the
plugin's state directory and is deleted on success. `uninstall` puts
`bindings.lua` back byte for byte and removes only what the plugin itself added,
so an edit you made after installing survives.

`uninstall` keeps your memories and your agent settings. `--purge` deletes both,
with no undo.

## Data

```
~/.config/omoide/config.json     which agent enriches captures
~/.local/share/omoide/           memories.db, blobs/     your captures
~/.local/state/omarchy/omoide/   index.json, rollback    derived, rebuildable
```

The agent settings are in a file of their own rather than inline on the bar
entry in `shell.json`. Writing them there meant racing the shell, which
hot-reloads that file and also rewrites it from memory, so a direct write could
be reverted seconds later. One writer means temp-and-rename is simply atomic.

The plugin never writes `shell.json`. It reads it for the two settings the shell
injects into a bar widget, `defaultAction` and `captureMode`, and those are
written only by `omarchy bar set` or by the shell itself when you pin a capture
mode from the menu.

SQLite with FTS5 for search. The schema version lives in `PRAGMA user_version`
and migrations run forward only. The CLI refuses to write a database from a
newer version of the plugin and exits 3, because a rolled-back checkout writing
against a schema it does not understand corrupts data without saying so.

`index.json` is a cache the CLI rewrites after every change. The QML reads that
and never touches SQLite, which keeps the bar and the library off the I/O path.

## Commands

```
capture   commit     discard    list     show      search   archive
state     item       reminder   sync-timers        collection
link      related    candidates block    delete
reindex   migrate    ai-config  setup-ai install   uninstall
```

`bin/omoide <command> --help` covers each one.

Over IPC:

```bash
omarchy-shell omoide capture screenshot
omarchy-shell omoide toggleSpace
omarchy-shell omoide state
```

Also `compose`, `closeCompose`, `openSpace`, `closeSpace`, `openSettings`,
`refresh` and `ping`.

## Two things worth knowing

The library is a centered layer-shell dialog, not a desktop window.
`FloatingWindow` never mapped under Hyprland here. The IPC call returned ok, no
window appeared, and nothing was logged. Omarchy's clipboard manager, emoji
picker and menu are all layer-shell surfaces too, and going that way gets
keyboard focus, Esc handling and theme colors without extra work.

Voice needs Voxtype. Without it the voice action and the dictate button render
disabled with the reason showing, rather than disappearing. Install it with
`omarchy-voxtype-install`.

## Not built yet

Export to markdown or PNG, clipboard capture, and calendar sync. The schema
already carries `rrule`, `all_day`, `trigger_offset_min` and the
`external_provider` / `external_id` / `external_etag` columns that sync needs.
