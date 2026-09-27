---
type: Reference
title: Keyboard model
description: How the Space window routes keys between the rail, the page and overlays, and the contract every page implements.
sources:
  - id: space
    resource: ../../../surfaces/SpaceWindow.qml
    title: handleKey, unwind, and focus restoration
  - id: library
    resource: ../../../views/LibraryView.qml
    title: A page implementing the contract
generated:
  by: anthropic/claude-opus-5-5
  at: '2026-09-26T00:00:00Z'
---

# Keyboard model

Read this before adding a page, an overlay, or a shortcut to the Space window. The window works without a mouse, and every key reaches its target through one router.

## Two depths

Focus lives at one of two depths, the rail or the page, and `inContent` in `surfaces/SpaceWindow.qml` says which. Opening at a section puts focus on the rail; opening a memory by id, or choosing a section, enters the page.

## The router

Keys reach `handleKey` at the default priority, so a focused text field consumes printable keys first. That is why `/` and `?` never fire mid-query, and why nothing checks whether a field is focused. In order:

1. While help is open, any key closes it.
2. **Esc** swallows auto-repeat, offers the key to the page, and otherwise unwinds one rung: the overflow menu, then an open overlay, then a sub-page, then the window itself.
3. While an overlay is open it owns the keyboard, and the window's own map goes dormant.
4. `?` opens help, Ctrl with a digit jumps to a section, and `/` goes to the library's search.
5. Anything else goes to the rail or to the page.

Every overlay takes focus when it opens and cannot hand it back, so the window calls `restoreFocus()` whenever one closes. A new overlay is wired the same way.

## Dialogs

Every dialog's root is a `FocusScope` with its Escape handler on that root. Key events travel up the focused item's parent chain, and `unwind()` leaves an open overlay to close itself, so a key catcher beside the content would miss keys from a focused button. A scope also keeps focus when the focused child is hidden or declines a key.

A field's first Esc releases focus into a plain `Item` inside the scope, never the scope itself, because a `FocusScope` hands focus back to the child it last had; the second Esc closes the dialog. Escape and Return ignore auto-repeat. Before hiding a focused control, move focus to one that stays visible: Qt drops focus from an invisible item, and then no key handler in the dialog fires.

The host's `PanelKeyCatcher` emits both `returnRequested` and `activateRequested` for one Enter, so a surface handles only one of them.

## The page contract

A page exposes `regionCount`, `region`, `focusFirst()` and `pageKey(event)`. Tab cycles `region`. `pageKey` returns false for a key the page did not use, which is how Left at the left edge returns to the rail without any page knowing the rail exists. A page that also has a search field exposes `focusInput()`.

A page draws its cursor only while `hasKeyboard` is true, and the window gives the keyboard to the rail or to the page, never both. Entering a region must seed its cursor explicitly, because setting `region` to its current value fires no change handler. Every card is focusable even when Enter does nothing on it, because the arrow keys are also how a page scrolls, and vertical keys cross section boundaries so a page reads as one column.
