// Setup: the agent, the keybinding, install and uninstall.
//
// Clean, not merely reversible: all-or-nothing, no residue outside our own
// directories, and idempotent in both directions.
#include "omoide.h"

#include <glib/gstdio.h>
#include <stdio.h>
#include <unistd.h>

#define DEFAULT_ACCEL "SUPER + CTRL + M"   // M for memory; E is Omarchy's emoji picker

static char *hypr_bindings_path(void) {
  return g_build_filename(g_get_home_dir(), ".config/hypr/bindings.lua", NULL);
}

// The line to paste into bindings.lua. Opens the chooser rather than capturing
// outright: a capture starts only from a click or Enter on a surface the shell
// drew itself.
static char *bindings_snippet(const char *accel) {
  return g_strdup_printf("o.bind(\"%s\", \"Omoide capture\",\n"
                         "       \"omarchy-shell -q %s toggleChooser\")", accel, IPC_TARGET);
}

static const struct { const char *name; int bit; } MOD_BITS[] = {
  { "SHIFT", 1 }, { "CAPS", 2 }, { "CTRL", 4 }, { "CONTROL", 4 }, { "ALT", 8 },
  { "MOD2", 16 }, { "MOD3", 32 }, { "SUPER", 64 }, { "MOD5", 128 },
};

// Ask Hyprland what is bound rather than parsing config by hand.
static char *keybind_conflict(const char *accel) {
  int64_t mask = 0;
  g_autofree char *key = g_strdup("");
  g_autofree char *trimmed = g_strstrip(g_strdup(accel));
  g_auto(GStrv) parts = g_regex_split(re("\\s*\\+\\s*", 0), trimmed, 0);
  for (size_t i = 0; parts[i]; i++) {
    g_autofree char *upper = g_utf8_strup(parts[i], -1);
    bool modifier = false;
    for (size_t m = 0; m < G_N_ELEMENTS(MOD_BITS); m++) {
      if (g_str_equal(upper, MOD_BITS[m].name)) {
        mask |= MOD_BITS[m].bit;
        modifier = true;
      }
    }
    if (!modifier) {
      g_free(key);
      key = g_utf8_strdown(parts[i], -1);
    }
  }

  const char *argv[] = { "hyprctl", "binds", "-j", NULL };
  g_auto(ProcResult) run = proc_run(argv, NULL, 0);
  if (run.status != 0)
    return NULL;
  g_autoptr(json_object) binds = json_tokener_parse(run.out);
  for (size_t i = 0; json_object_is_type(binds, json_type_array)
                     && i < json_object_array_length(binds); i++) {
    json_object *bind = json_object_array_get_idx(binds, i);
    int64_t modmask = -1;
    if (json_get(bind, "modmask"))
      as_int(json_get(bind, "modmask"), &modmask);
    g_autofree char *bound_key = as_text(json_get(bind, "key"));
    g_autofree char *bound_lower = g_utf8_strdown(bound_key, -1);
    if (modmask != mask || !g_str_equal(bound_lower, key))
      continue;
    g_autofree char *dispatcher = as_text(json_get(bind, "dispatcher"));
    g_autofree char *argument = as_text(json_get(bind, "arg"));
    if (strstr(argument, IPC_TARGET))
      return NULL;      // our own binding, already installed
    g_autofree char *both = g_strdup_printf("%s %s", dispatcher, argument);
    return g_strstrip(g_strdup(both));
  }
  return NULL;
}

// Print a binding for the user to add themselves. A keybinding is the user's
// own configuration, and a plugin that edits it has to be trusted to edit it
// back; handing over the line to paste needs no trust and leaves no residue.
int cmd_keybind(int argc, char **argv) {
  g_autofree char *accel_arg = NULL;
  gboolean as_json = FALSE;
  const GOptionEntry entries[] = {
    { "accel", 0, 0, G_OPTION_ARG_STRING, &accel_arg, NULL, "CHORD" },
    { "json", 0, 0, G_OPTION_ARG_NONE, &as_json, NULL, NULL },
    G_OPTION_ENTRY_NULL
  };
  parse_options("keybind", entries, 0, &argc, &argv);
  const char *accel = accel_arg && *accel_arg ? accel_arg : DEFAULT_ACCEL;
  g_autofree char *snippet = bindings_snippet(accel);
  g_autofree char *conflict = keybind_conflict(accel);
  if (as_json) {
    g_autofree char *file = hypr_bindings_path();
    json_object *out = json_object_new_object();
    json_object_object_add(out, "accel", json_object_new_string(accel));
    json_object_object_add(out, "snippet", json_object_new_string(snippet));
    json_object_object_add(out, "file", json_object_new_string(file));
    json_object_object_add(out, "conflict", json_str(conflict));
    emit(out);
    return 0;
  }
  puts(snippet);
  // Reported, not enforced: they may well be replacing the binding they have.
  if (conflict)
    fprintf(stderr, "\n# note: %s currently runs: %s\n", accel, conflict);
  return 0;
}

static ProcResult omarchy(const char *a, const char *b, const char *c, const char *d,
                          const char *e, const char *f) {
  const char *argv[] = { "omarchy", a, b, c, d, e, f, NULL };
  return proc_run(argv, NULL, 0);
}

// ~/.local/bin/omoide, so the CLI can be run by name. Omarchy puts that
// directory on PATH. Only ever a symlink of ours: anything else already there
// belongs to someone else and is left alone.
static char *command_link_path(void) {
  return g_build_filename(g_get_home_dir(), ".local/bin/omoide", NULL);
}

static bool is_our_link(const char *link) {
  g_autofree char *target = g_file_read_link(link, NULL);
  g_autofree char *ours = cache_bin_path();
  return target && g_str_equal(target, ours);
}

static char *link_command(void) {
  g_autofree char *link = command_link_path();
  if (g_file_test(link, G_FILE_TEST_EXISTS | G_FILE_TEST_IS_SYMLINK) && !is_our_link(link))
    return NULL;
  g_autofree char *dir = g_path_get_dirname(link);
  g_autofree char *target = cache_bin_path();
  g_mkdir_with_parents(dir, 0777);
  g_unlink(link);
  return symlink(target, link) == 0 ? g_steal_pointer(&link) : NULL;
}

int cmd_install(int argc, char **argv) {
  g_autofree char *accel = NULL;
  const GOptionEntry entries[] = {
    { "accel", 0, 0, G_OPTION_ARG_STRING, &accel, "the chord to suggest", "CHORD" },
    G_OPTION_ENTRY_NULL
  };
  parse_options("install", entries, 0, &argc, &argv);
  db_open(true);   // create + migrate the database before anything user-visible

  {
    g_auto(ProcResult) enable = omarchy("plugin", "enable", PLUGIN_ID, NULL, NULL, NULL);
    if (enable.status != 0) {
      g_autofree char *why = g_strstrip(g_strdup(*enable.err ? enable.err
                                                 : *enable.out ? enable.out : "plugin enable"));
      die(1, "install failed (%s); rolled back", why);
    }
  }
  {
    const char *put_argv[] = { "omarchy", "bar", "put", PLUGIN_ID, "--section", "right",
                               "--after", "omarchy.agents", NULL };
    g_auto(ProcResult) put = proc_run(put_argv, NULL, 0);
    (void)put;
  }
  shell_ipc("shell", "rescanPlugins", NULL);
  g_autofree char *link = link_command();

  // No keybinding is installed. The bar icon is the entry point; anyone wanting
  // a chord runs `omoide keybind` and pastes the line themselves.
  g_autofree char *snippet = bindings_snippet(accel && *accel ? accel : DEFAULT_ACCEL);
  g_autofree char *file = hypr_bindings_path();
  g_autoptr(json_object) ai = ai_settings();
  g_auto(GStrv) provider = resolve_provider(ai);
  json_object *out = json_object_new_object();
  json_object_object_add(out, "installed", json_object_new_boolean(true));
  json_object_object_add(out, "keybind", json_object_new_string(snippet));
  json_object_object_add(out, "keybindFile", json_object_new_string(file));
  json_object_object_add(out, "aiConfigured", json_object_new_boolean(provider != NULL));
  json_object_object_add(out, "command", json_str(link));
  emit(out);
  return 0;
}

int cmd_uninstall(int argc, char **argv) {
  gboolean purge = FALSE;
  const GOptionEntry entries[] = {
    { "purge", 0, 0, G_OPTION_ARG_NONE, &purge, "also delete captured memories (irreversible)", NULL },
    G_OPTION_ENTRY_NULL
  };
  parse_options("uninstall", entries, 0, &argc, &argv);
  // Before anything is disabled or deleted: this is the one command that
  // deletes, so refusing a state directory inside the package tree matters
  // more here than anywhere.
  guard_paths();

  // Nothing to undo in bindings.lua: the plugin never wrote there. Nothing to
  // unschedule either: an alarm is a row here and a timer in the shell.
  {
    g_auto(ProcResult) disable = omarchy("plugin", "disable", PLUGIN_ID, NULL, NULL, NULL);
    (void)disable;
  }

  const Paths *p = paths();
  // Every tree removed here is ours by construction -- see paths.c -- so
  // there is nothing to recognise before deleting it.
  remove_tree(p->state_dir);          // derived: always removed
  g_autofree char *link = command_link_path();
  if (is_our_link(link))
    g_unlink(link);
  g_autofree char *binary = cache_bin_path();
  g_autofree char *bin_dir = g_path_get_dirname(binary);
  g_autofree char *cache_dir = g_path_get_dirname(bin_dir);
  remove_tree(cache_dir);             // the built CLI: derived too

  bool data_removed = false;
  if (purge) {
    remove_tree(p->data_dir);
    // Reported, not assumed: a permission problem is not an error here, and a
    // symlinked root is declined rather than followed.
    data_removed = !g_file_test(p->data_dir, G_FILE_TEST_EXISTS);
    // Our own settings. Kept by a plain uninstall, like the captures: the
    // agent you chose is yours, not installation state.
    g_unlink(p->config_path);
  }

  shell_ipc("shell", "rescanPlugins", NULL);
  json_object *out = json_object_new_object();
  json_object_object_add(out, "uninstalled", json_object_new_boolean(true));
  json_object_object_add(out, "dataRemoved", json_object_new_boolean(data_removed));
  json_object_object_add(out, "dataDir", data_removed ? NULL : json_object_new_string(p->data_dir));
  json_object_object_add(out, "configFile", purge ? NULL : json_object_new_string(p->config_path));
  emit(out);
  return 0;
}

// --- the agent

// What each provider's restriction actually is, for the settings dialog, in
// ocr and image mode. The argv shows most of it, but opencode's lives in an
// environment variable and so does gemini's workspace trust.
static const struct { const char *name, *ocr, *image; } RESTRICTIONS[] = {
  { "claude", "tools disabled", "no tools but reading the screenshot" },
  { "codex", "shell tool off, read-only sandbox behind it", "shell tool off, read-only sandbox behind it" },
  { "gemini", "read-only mode", "read-only mode" },
  { "opencode", "every tool permission denied", "every tool permission denied" },
};

static bool plain_model(const char *name) {
  return g_str_equal(name, "ollama") || g_str_equal(name, "aichat");
}

static bool vision_capable(const char *name) {
  return g_str_equal(name, "claude") || g_str_equal(name, "codex")
         || g_str_equal(name, "gemini") || g_str_equal(name, "opencode");
}

// argv as a line someone can read, with empty arguments made visible.
static char *display_argv(char **argv) {
  g_autoptr(GString) line = g_string_new(NULL);
  for (size_t i = 0; argv[i]; i++) {
    if (i)
      g_string_append_c(line, ' ');
    g_string_append(line, *argv[i] ? argv[i] : "''");
  }
  return g_string_free(g_steal_pointer(&line), FALSE);
}

// A custom command is stored as `sh -c <what was typed>`, and the dialog
// shows -- and saves back -- what was typed. Reporting the wrapper would have
// the next save wrap it a second time.
static json_object *command_for_display(json_object *command) {
  if (json_object_is_type(command, json_type_array) && json_object_array_length(command) == 3
      && g_strcmp0(json_object_get_string(json_object_array_get_idx(command, 0)), "sh") == 0
      && g_strcmp0(json_object_get_string(json_object_array_get_idx(command, 1)), "-c") == 0) {
    json_object *typed = json_object_new_array();
    json_object_array_add(typed, json_object_get(json_object_array_get_idx(command, 2)));
    return typed;
  }
  return truthy(command) ? json_object_get(command) : json_object_new_array();
}

// Everything the settings dialog needs to render itself.
int cmd_ai_config(int argc, char **argv) {
  parse_options("ai-config", NULL, 0, &argc, &argv);
  g_autoptr(json_object) current = ai_settings();

  json_object *providers = json_object_new_array();
  for (size_t i = 0; i < ai_preset_count(); i++) {
    const char *name = ai_preset_name(i);
    const char *const *preset = ai_preset_argv(i);
    // The command the dialog shows is the command that runs, hardening
    // included: both come from harden(), so they cannot disagree.
    const bool plain = plain_model(name);
    g_auto(GStrv) ocr_argv = plain ? g_strdupv((char **)preset)
                                   : harden(preset, name, false, NULL, NULL);
    g_auto(GStrv) image_argv = plain ? g_strdupv((char **)preset)
                                     : harden(preset, name, true, "<capture>/screenshot.png", NULL);
    const char *restriction = "", *restriction_image = "";
    for (size_t r = 0; r < G_N_ELEMENTS(RESTRICTIONS); r++) {
      if (g_str_equal(RESTRICTIONS[r].name, name)) {
        restriction = RESTRICTIONS[r].ocr;
        restriction_image = RESTRICTIONS[r].image;
      }
    }
    g_autofree char *command = display_argv(ocr_argv);
    g_autofree char *command_image = display_argv(image_argv);
    json_object *entry = json_object_new_object();
    json_object_object_add(entry, "id", json_object_new_string(name));
    json_object_object_add(entry, "command", json_object_new_string(command));
    json_object_object_add(entry, "commandImage", json_object_new_string(command_image));
    json_object_object_add(entry, "restriction", json_object_new_string(restriction));
    json_object_object_add(entry, "restrictionImage", json_object_new_string(restriction_image));
    json_object_object_add(entry, "available", json_object_new_boolean(has(preset[0])));
    json_object_object_add(entry, "vision", json_object_new_boolean(vision_capable(name)));
    json_object_object_add(entry, "needsModel", json_object_new_boolean(g_str_equal(name, "ollama")));
    json_object_array_add(providers, entry);
  }

  g_auto(GStrv) resolved = resolve_provider(current);
  int64_t timeout = 45000;
  if (truthy(json_get(current, "timeoutMs")))
    as_int(json_get(current, "timeoutMs"), &timeout);
  json_object *provider = json_get(current, "provider");
  json_object *model = json_get(current, "model");
  json_object *vision = json_get(current, "visionMode");
  json_object *out = json_object_new_object();
  json_object_object_add(out, "enabled", json_object_new_boolean(truthy(json_get(current, "enabled"))));
  json_object_object_add(out, "provider", truthy(provider) ? json_object_get(provider) : json_object_new_string(""));
  json_object_object_add(out, "command", command_for_display(json_get(current, "command")));
  json_object_object_add(out, "model", truthy(model) ? json_object_get(model) : json_object_new_string(""));
  json_object_object_add(out, "visionMode", truthy(vision) ? json_object_get(vision) : json_object_new_string("ocr"));
  json_object_object_add(out, "timeoutMs", json_object_new_int64(timeout));
  json_object_object_add(out, "providers", providers);
  json_object_object_add(out, "resolved", json_object_new_boolean(resolved != NULL));
  emit(out);
  return 0;
}

static const char *const VISION_MODES[] = { "ocr", "image", NULL };

int cmd_setup_ai(int argc, char **argv) {
  g_autofree char *provider_arg = NULL, *command = NULL, *model = NULL, *vision = NULL;
  gboolean disable = FALSE;
  const GOptionEntry entries[] = {
    { "provider", 0, 0, G_OPTION_ARG_STRING, &provider_arg, NULL, "NAME" },
    { "command", 0, 0, G_OPTION_ARG_STRING, &command,
      "the command for a custom provider, run with sh -c", "COMMAND" },
    { "model", 0, 0, G_OPTION_ARG_STRING, &model, NULL, "MODEL" },
    { "vision", 0, 0, G_OPTION_ARG_STRING, &vision, "ocr or image", "MODE" },
    { "disable", 0, 0, G_OPTION_ARG_NONE, &disable, NULL, NULL },
    G_OPTION_ENTRY_NULL
  };
  parse_options("setup-ai", entries, 0, &argc, &argv);
  if (vision)
    require_choice("setup-ai", "--vision", vision, VISION_MODES);
  g_autoptr(json_object) current = ai_settings();

  if (disable) {
    json_object_object_add(current, "enabled", json_object_new_boolean(false));
    write_ai_settings(current);
    json_object *out = json_object_new_object();
    json_object_object_add(out, "enabled", json_object_new_boolean(false));
    emit(out);
    return 0;
  }

  g_autofree char *provider = g_strdup(provider_arg);
  if (!provider || !*provider) {
    g_autoptr(GStrvBuilder) names = g_strv_builder_new();
    g_autoptr(GStrvBuilder) choose = g_strv_builder_new();
    g_strv_builder_add_many(choose, "gum", "choose", "--header", "Agent for Omoide:", NULL);
    for (size_t i = 0; i < ai_preset_count(); i++) {
      g_strv_builder_add(names, ai_preset_name(i));
      if (has(ai_preset_name(i)))
        g_strv_builder_add(choose, ai_preset_name(i));
    }
    g_strv_builder_add(choose, "custom");
    if (!has("gum")) {
      g_auto(GStrv) all = g_strv_builder_end(names);
      g_autofree char *listed = g_strjoinv(", ", all);
      die(1, "pass --provider (one of: %s, custom)", listed);
    }
    g_auto(GStrv) picker = g_strv_builder_end(choose);
    g_auto(ProcResult) picked = proc_run((const char *const *)picker, NULL, 0);
    g_free(provider);
    provider = g_strstrip(g_strdup(picked.out ? picked.out : ""));
    if (!*provider)
      return 2;
  }

  if (g_str_equal(provider, "custom")) {
    if (!command || !*command)
      die(1, "--command is required with --provider custom");
    g_autofree char *typed = strip_space(command);
    if (!*typed)
      die(1, "--command is empty");
    // Run by a shell, exactly as typed: quotes, variables and pipes mean what
    // they mean in a terminal, and nothing here has to re-implement that. The
    // command is the user's own; captured text reaches it on stdin only.
    json_object *argv_json = json_object_new_array();
    json_object_array_add(argv_json, json_object_new_string("sh"));
    json_object_array_add(argv_json, json_object_new_string("-c"));
    json_object_array_add(argv_json, json_object_new_string(typed));
    json_object_object_add(current, "command", argv_json);
    json_object_object_add(current, "provider", json_object_new_string("custom"));
    // Said plainly, because it is the one configuration where none of the
    // tool restrictions apply.
    fputs("omoide: a custom command is run as given. Omoide cannot switch off its tools,\n"
          "        and a capture is OCR of whatever was on screen. Add your agent's own\n"
          "        read-only or no-tools flag to --command.\n", stderr);
  } else if (is_ai_preset(provider)) {
    json_object_object_add(current, "provider", json_object_new_string(provider));
    json_object_object_add(current, "command", json_object_new_array());
    if (!has(provider))
      die(1, "%s is not on PATH", provider);
    if (!plain_model(provider))
      fprintf(stderr, "omoide: %s runs with its tools switched off and an empty working "
                      "directory.\n", provider);
  } else {
    die(1, "unknown provider: %s", provider);
  }

  if (model)
    json_object_object_add(current, "model", json_object_new_string(model));
  if (vision)
    json_object_object_add(current, "visionMode", json_object_new_string(vision));
  json_object_object_add(current, "enabled", json_object_new_boolean(true));
  write_ai_settings(current);

  json_object *out = json_object_new_object();
  json_object_object_add(out, "enabled", json_object_new_boolean(true));
  json_object_object_add(out, "provider", json_object_get(json_get(current, "provider")));
  json_object_object_add(out, "command", json_object_get(json_get(current, "command")));
  json_object_object_add(out, "visionMode", json_object_get(json_get(current, "visionMode")));
  emit(out);
  return 0;
}
