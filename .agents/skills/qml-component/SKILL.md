---
name: qml-component
description: Add, move, split or restyle a QML file in the plugin. Covers choosing its directory, imports, sizing and color from qs.Commons, focus and keyboard reachability, plain-text rendering, calling the CLI through the service, and verifying with check-types, qmllint and the live shell. Use for any change to a .qml file or MemoryModel.js. Do not use for the plugin's entry points or IPC, which follow the Omarchy host reference.
---

# QML component

The rules are in [the engineering standard](../../docs/engineering/code-style.md#qml), including which directory holds what and what it may import. `ui/common/AGENTS.md` adds the rules for shared primitives.

## Steps

1. **Look first.** Before writing a new component, check `ui/common/` and `ui/components/` for one that already does it, and extend it with a property rather than copying it.
2. **Place it** by what it is, not where it is first used. A card used only by the library is still a component if a second page could use it.
3. **Import** directories unqualified and JavaScript files with an alias. Moving a file changes every import that reached it: search for its name across the tree, and let `dev/check-types` confirm.
4. **Build it from the kit.** Sizes from `Style.space()`, type from `Style.font`, colors from `Color`, radii from `Radii.nested` inside a bordered card, focus with `FocusRing`. Text a user or an agent wrote is `Text.PlainText`.
5. **Make it reachable by keyboard.** A page implements the contract `ui/surfaces/SpaceWindow.qml` routes keys through; a dialog handles its own Esc and gives focus back when it closes.
6. **Talk to the CLI through `service`.** `service.call` when the result is needed, `service.detach` when the work must outlive a reload. Put date formatting and other pure logic in `MemoryModel.js`.
7. **Verify.** `dev/check --no-cli` runs `dev/check-types` and qmllint. Then load `verify-in-shell`: a component under `ui/components/` or `ui/common/` needs a shell restart to load at all.
