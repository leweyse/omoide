# Changelog

## 0.5.2

### Patch Changes

- [#13](https://github.com/leweyse/omoide/pull/13) [`38bf685`](https://github.com/leweyse/omoide/commit/38bf6856bcc31d8029db524744380fc8eda1c55d) Thanks [@leweyse](https://github.com/leweyse)! - fix(security): a title starting with a dash can change what its notification shows or replaces

- [#13](https://github.com/leweyse/omoide/pull/13) [`38bf685`](https://github.com/leweyse/omoide/commit/38bf6856bcc31d8029db524744380fc8eda1c55d) Thanks [@leweyse](https://github.com/leweyse)! - fix(security): text on a captured screen can get the gemini agent to run commands
  
  - Gemini now runs with every tool denied, web search included
  - With "the screenshot itself" chosen, gemini sees the screenshot instead of describing something else

- [#13](https://github.com/leweyse/omoide/pull/13) [`38bf685`](https://github.com/leweyse/omoide/commit/38bf6856bcc31d8029db524744380fc8eda1c55d) Thanks [@leweyse](https://github.com/leweyse)! - fix(security): claude, codex and opencode keep tools a captured page could steer them into using
  
  - Claude no longer gets your MCP servers, and in screenshot mode reads nothing but the screenshot
  - Codex no longer has web search or an image viewer that can open any picture on disk
  - Opencode denies every tool, including web search, skills and MCP tools, even when your own config allows them

## 0.5.1

### Patch Changes

- [#10](https://github.com/leweyse/omoide/pull/10) [`4f8fc25`](https://github.com/leweyse/omoide/commit/4f8fc2598d775053852446ff2861b93014b45cf5) Thanks [@leweyse](https://github.com/leweyse)! - fix: a fresh install of Omoide fails `omarchy plugin validate`

## 0.5.0

### Minor Changes

- [#6](https://github.com/leweyse/omoide/pull/6) [`e1962e2`](https://github.com/leweyse/omoide/commit/e1962e266983d28d37a93176e6bf568eee0fcf28) Thanks [@leweyse](https://github.com/leweyse)! - feat(cli): Omoide builds its own command-line tool when the shell loads it, and no longer needs Python
  
  The first load after installing or updating takes a moment longer while it builds.

- [#6](https://github.com/leweyse/omoide/pull/6) [`e1962e2`](https://github.com/leweyse/omoide/commit/e1962e266983d28d37a93176e6bf568eee0fcf28) Thanks [@leweyse](https://github.com/leweyse)! - feat(library,tasks): the library, tasks and events load as you scroll, however many there are
  
  - Placeholders hold the place of whatever is still loading, on every page
  - Cards already on screen stay put while the next page arrives

- [#6](https://github.com/leweyse/omoide/pull/6) [`e1962e2`](https://github.com/leweyse/omoide/commit/e1962e266983d28d37a93176e6bf568eee0fcf28) Thanks [@leweyse](https://github.com/leweyse)! - feat(space): coming back to a page picks up where you left it
  
  The item you last touched is highlighted again, and the scroll, search and chip are as you left them.

### Patch Changes

- [#6](https://github.com/leweyse/omoide/pull/6) [`e1962e2`](https://github.com/leweyse/omoide/commit/e1962e266983d28d37a93176e6bf568eee0fcf28) Thanks [@leweyse](https://github.com/leweyse)! - fix(ui): borders, focus marks and corners look inconsistent across cards, badges and buttons
  
  - Library: card borders break at some screen resolutions
  - Events and collections: a card loses its top border while the row is scrolled
  - Cards: focus shows as corner marks everywhere, and badges and buttons follow the theme's corner rounding

- [#6](https://github.com/leweyse/omoide/pull/6) [`e1962e2`](https://github.com/leweyse/omoide/commit/e1962e266983d28d37a93176e6bf568eee0fcf28) Thanks [@leweyse](https://github.com/leweyse)! - fix(space): a library saved by a newer Omoide opens as an empty page

- [#6](https://github.com/leweyse/omoide/pull/6) [`e1962e2`](https://github.com/leweyse/omoide/commit/e1962e266983d28d37a93176e6bf568eee0fcf28) Thanks [@leweyse](https://github.com/leweyse)! - fix(space,library): the keyboard highlight is left behind or off screen
  
  - Library: moving up from the captures leaves the collections off screen
  - Every page: a card or block stays highlighted after the keyboard leaves it

- [#6](https://github.com/leweyse/omoide/pull/6) [`e1962e2`](https://github.com/leweyse/omoide/commit/e1962e266983d28d37a93176e6bf568eee0fcf28) Thanks [@leweyse](https://github.com/leweyse)! - fix(bar): the open to-do count stops at 200

- [#6](https://github.com/leweyse/omoide/pull/6) [`e1962e2`](https://github.com/leweyse/omoide/commit/e1962e266983d28d37a93176e6bf568eee0fcf28) Thanks [@leweyse](https://github.com/leweyse)! - fix(space): rows that scroll sideways barely move on a touchpad and snap back
  
  Swiping up or down over a row now scrolls the page.

- [#6](https://github.com/leweyse/omoide/pull/6) [`e1962e2`](https://github.com/leweyse/omoide/commit/e1962e266983d28d37a93176e6bf568eee0fcf28) Thanks [@leweyse](https://github.com/leweyse)! - fix(capture): taking a screenshot does nothing
