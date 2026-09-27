---
type: Reference
title: Omarchy host
description: How the Omarchy shell finds, loads, reloads and exposes the plugin, and the IPC surface users bind.
source_digest: 'sha256:88404ac2f8997833fd0ce14c06338e5f0541aa36707228f5a44e8743deee1e16'
sources:
  - id: manifest
    resource: ../../../manifest.json
    title: Plugin manifest
  - id: service
    resource: ../../../ui/Service.qml
    title: Service entry point and IPC handler
  - id: widget
    resource: ../../../ui/BarWidget.qml
    title: Bar widget entry point
generated:
  by: anthropic/claude-opus-5-5
  at: '2026-09-26T00:00:00Z'
---

# Omarchy host

Read this before changing `manifest.json`, an entry point, the IPC handler, or anything about how the plugin is loaded. The host's own source is under the shell install (`services/PluginRegistry.qml`, `shell.qml`, `Ui/BarWidget.qml`), outside this repository, and it changes on Omarchy's schedule. Verify against it rather than against this page when the two disagree, then fix this page.

## Loading

The shell scans the top-level directories of the user's plugins folder for a `manifest.json`, validates it, and loads a third-party plugin only when the user's `shell.json` references it; a bar placement counts. The manifest names two entry points, both under `ui/`. The host accepts an entry point in a subfolder and rejects one that is absolute or contains `..`:

- **`ui/Service.qml`** is created once, with no parent, and kept across plugin reloads because the manifest sets `keepLoaded`. The host injects `omarchyPath`, `shell`, and `manifest` if the instance declares them. Anything that must exist once lives here: the IPC target, the CLI build, the index pull on `refresh`, reminder timers, and the loaders for the Space window, the compose overlay and settings.
- **`ui/BarWidget.qml`** extends the host's `BarWidget` and is created once per monitor. It reaches the service through `bar.shell.serviceFor("leweyse.omoide")`, which returns only this plugin's own service, and writes its settings back through `bar.shell.updateEntryInline`.

The host strips `__sourceDir` from a third-party manifest before handing it over. The plugin therefore resolves its own root from `Qt.resolvedUrl("..")` in `ui/Service.qml`, one level above the file, never from the manifest.

## Reloading

The shell watches the plugins folder with `inotifywait` and reloads plugins shortly after any change, ignoring dotfiles and `.git/`. A reload rebuilds widgets and non-kept services and clears the component cache.

Because `Service.qml` is kept, a reload does not re-run it, and everything its loaders created stays as it was. An edit to `Service.qml`, to a component under `ui/components/`, or to anything a kept surface loaded is not picked up until `omarchy-restart-shell`. The `verify-in-shell` skill covers this in practice.

Anything written into the plugin directory triggers the watcher, and an untracked or modified file there makes `omarchy plugin update`'s fast-forward pull fail. That is why the CLI is built into the user's cache directory and why nothing at runtime writes into the checkout.

## Surfaces

The bar widget's `open`, `close`, `opened` and `toggle` live on `BarWidget.qml` itself, not on the menu it shows, because the bar matches its active popout by object identity against the item it loaded from the manifest.

Every window the plugin opens is a Wayland layer, a `PanelWindow` with its own `WlrLayershell.namespace`, so none of them appears in `hyprctl clients`. Look for them with `hyprctl layers`. The Space window takes exclusive keyboard focus while open.

## IPC

`Service.qml` declares one `IpcHandler` with target `omoide`. Its functions are a user-facing contract: users call them from `bindings.lua`, the CLI calls them back, and notifications carry them as click actions. Renaming one, removing one, or changing what its argument means needs approval.

Read the handler for the current list and the argument each takes. Two properties are deliberate and must survive any change:

- **IPC opens windows; it does not act.** There is no capture function. The keybind opens the capture chooser (`toggleChooser`), and a capture starts only from a click or Enter on a surface the shell drew itself.
- **A payload cannot start the microphone.** `compose` honors `autoDictate` only with the one-time ticket `capture()` issued, and spends the ticket whether or not it was used.
- **Payloads are JSON strings.** `openSpace`, `toggleSpace` and `compose` take one string argument and parse it, so a new field is additive and an old caller keeps working.

## Manifest

`manifest.json` is read by the host and by the CLI, which embeds it at build time for `--version`. Its `id`, its `entryPoints` and its `barWidget.schema` keys are stored in users' `shell.json`, so changing any of them breaks existing installs. `version` changes only through `dev/changeset version`, in the release pull request the `release` skill describes, and `dev/sync-docs` ignores its value so a release does not stale this page.
