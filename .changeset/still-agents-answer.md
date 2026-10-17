---
"omoide": patch
---

fix(security): claude, codex and opencode keep tools a captured page could steer them into using

- Claude no longer gets your MCP servers, and in screenshot mode reads nothing but the screenshot
- Codex no longer has web search or an image viewer that can open any picture on disk
- Opencode denies every tool, including web search, skills and MCP tools, even when your own config allows them
