# common

Read this before adding a primitive here or restyling one. Everything in `ui/common/` is used across the plugin, so a change to one file changes every surface that uses it. `grep -rl` for its name before editing.

## Invariants

- **A primitive knows nothing about memories.** It imports only `qs.*`, never another plugin directory and never `MemoryModel.js`. `MasonryGrid.qml` is the one exception, because its cursor is addressed by memory id; do not add a second.
- **Extend a primitive instead of forking it.** A field that needs a different Esc behavior gets a property on `AccentField`, not a copy. A second button with the same focus treatment as `DialogButton` is a bug in waiting.
- **Focus is drawn, not laid out.** `FocusRing` is an overlay inset from the border, so focusing a control never moves anything. A primitive that is focusable uses it.
- **Focus borders are `Border.flat`, never `Border.controlSpec("focus")`.** The kit's focus variant applies a shell-wide alpha that makes focus hard to see. At rest a card uses the outline-button border, not `popups.border`, which defaults to the accent. A focus border never changes width, because a card's height includes its border and a wider one would reflow the grid on every arrow key.
- **`AccentField` and `AccentTextArea` share a focus language by hand.** Their base types differ, because a `TextInput` cannot wrap, so a change to one's border, corner marks, fill or Esc handling is made in both.
- **Radii nest.** An element inside a rounded border takes its radius from `Radii.nested(outer, border)` in `Radii.js`, so corners stay concentric at every scale.
- **Sizes and colors come from `qs.Commons`.** `Style.space()`, `Style.font` and the `Color` tokens; no literal pixel values.

## Verify

A change here reaches every dialog. Open the Space window after `omarchy-restart-shell`, since the plugin watcher does not reload files in this directory, and check the log; the `verify-in-shell` skill covers both.
