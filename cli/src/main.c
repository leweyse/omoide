#include "omoide.h"

#include <signal.h>
#include <stdio.h>
#include <string.h>

typedef struct {
  const char *name;
  const char *alias;
  const char *help;
  int (*run)(int argc, char **argv);
} Command;

// The order `omoide --help` lists them in.
static const Command COMMANDS[] = {
  { "capture", NULL, "start a capture", cmd_capture },
  { "commit", NULL, "finalise a draft and enrich it", cmd_commit },
  { "discard", NULL, "throw a draft away", cmd_discard },
  { "list", NULL, "recent memories", cmd_list },
  { "show", NULL, "one memory, with blocks and items", cmd_show },
  { "search", NULL, "full-text search", cmd_search },
  { "archive", NULL, "to-dos grouped for the archive view", cmd_archive },
  { "state", NULL, "counts for the bar widget", cmd_state },
  { "item", NULL, "to-do and event operations", cmd_item },
  { "reminder", NULL, "alarms attached to an item", cmd_reminder },
  // sync-timers is what shells older than this release call on startup.
  { "sweep", "sync-timers", "deliver late alarms and clear dead drafts", cmd_sweep },
  { "collection", NULL, "collections", cmd_collection },
  { "link", NULL, "related captures", cmd_link },
  { "related", NULL, "captures linked to this one", cmd_related },
  { "candidates", NULL, "memories available to link by hand", cmd_candidates },
  { "block", NULL, "edit or delete one block", cmd_block },
  { "delete", NULL, "delete a memory and everything under it", cmd_delete },
  { "memory", NULL, "edit a memory's title or lede", cmd_memory },
  { "enrich", NULL, "run the agent again on an existing capture", cmd_enrich },
  { "reindex", NULL, "rebuild the search index and the QML cache", cmd_reindex },
  { "migrate", NULL, "apply pending schema migrations", cmd_migrate },
  { "ai-config", NULL, "the configured agent, and which agents are installed", cmd_ai_config },
  { "setup-ai", NULL, "choose the agent that enriches captures", cmd_setup_ai },
  { "install", NULL, "enable the plugin and place the bar widget", cmd_install },
  { "keybind", NULL, "print a keybinding to paste into hypr/bindings.lua", cmd_keybind },
  { "uninstall", NULL, "remove everything this plugin added", cmd_uninstall },
};

static void usage(FILE *to) {
  fputs("usage: omoide <command> [options]\n\n"
        "Capture, enrich and recall Omoide memories.\n\n"
        "commands:\n",
      to);
  for (size_t i = 0; i < G_N_ELEMENTS(COMMANDS); i++)
    fprintf(to, "  %-12s %s\n", COMMANDS[i].name, COMMANDS[i].help);
  fputs("\n  --version    the plugin version and the source this was built from\n", to);
}

static int version(void) {
  json_object *out = json_object_new_object();
  json_object_object_add(out, "version", json_object_new_string(plugin_version()));
  json_object_object_add(out, "source", json_object_new_string(OMOIDE_SRC_ID));
  emit(out);
  return 0;
}

int main(int argc, char **argv) {
  // A reader that goes away early (`| head`) is not an error worth a signal.
  signal(SIGPIPE, SIG_IGN);

  if (argc < 2) {
    usage(stderr);
    return 2;
  }
  const char *name = argv[1];
  if (strcmp(name, "--version") == 0)
    return version();
  if (strcmp(name, "-h") == 0 || strcmp(name, "--help") == 0) {
    usage(stdout);
    return 0;
  }

  for (size_t i = 0; i < G_N_ELEMENTS(COMMANDS); i++) {
    const Command *c = &COMMANDS[i];
    if (strcmp(name, c->name) != 0 && g_strcmp0(name, c->alias) != 0)
      continue;
    // The command sees itself as argv[0], so its options parse like a
    // program of their own.
    return c->run(argc - 1, argv + 1);
  }

  usage(stderr);
  die(2, "invalid command: '%s'", name);
}
