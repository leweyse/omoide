---
"omoide": patch
---

fix(security): codex reading a capture could still use the MCP servers in its config, and its apps and plugins

Text on a captured screen could ask a read-only MCP tool, such as a filesystem server, to read a private file into the agent's reply. Codex now starts with none of these, and with browser and computer use off. It also skips its own config file in this mode; if you set its model or provider there, allow one of its MCP servers in Settings and the file is read again.
