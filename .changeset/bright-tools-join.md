---
"omoide": minor
---

feat(cli,menu): Settings lets you allow web search and individual MCP servers for your agent

"Choose an agent…" is now "Settings…". It lists the MCP servers your agent already has, and nothing is allowed until you tick it; each agent then runs with only what you ticked. The shell stays off and the sandbox read-only either way. From a terminal, `omoide ai-servers --provider <agent>` lists the servers and `omoide setup-ai --allow web_search --allow mcp:<server>` saves the choice.
