#include "omoide.h"

// Headless, prompt-on-stdin invocations. Each must run to completion without
// a TTY and print the answer on stdout.
static const struct {
  const char *name;
  const char *argv[5];
} AI_PRESETS[] = {
  { "claude",   { "claude", "-p" } },
  { "codex",    { "codex", "exec", "--skip-git-repo-check", "-" } },
  { "opencode", { "opencode", "run" } },
  // -p takes a value, and a bare `gemini -p` with the prompt on stdin fails
  // argument parsing. The empty value selects headless mode while leaving
  // stdin as the whole prompt; putting a screen's worth of OCR in argv would
  // publish it to `ps`.
  { "gemini",   { "gemini", "-p", "" } },
  { "ollama",   { "ollama", "run" } },     // model appended
  { "aichat",   { "aichat" } },
};

static json_object *default_ai(void) {
  json_object *ai = json_object_new_object();
  json_object_object_add(ai, "enabled", json_object_new_boolean(false));
  json_object_object_add(ai, "provider", json_object_new_string("claude"));
  json_object_object_add(ai, "command", json_object_new_array());
  json_object_object_add(ai, "model", json_object_new_string(""));
  json_object_object_add(ai, "visionMode", json_object_new_string("ocr"));
  json_object_object_add(ai, "timeoutMs", json_object_new_int(45000));
  return ai;
}

// The agent block, merged over the shipped defaults. A missing or unreadable
// file is not an error: it means nothing has been configured, which is the
// shipped state.
json_object *ai_settings(void) {
  json_object *merged = default_ai();
  g_autoptr(json_object) stored = json_object_from_file(paths()->config_path);
  json_object *ai = json_get(stored, "ai");
  if (!ai || !json_object_is_type(ai, json_type_object))
    return merged;
  json_object_object_foreach(ai, key, value)
    json_object_object_add(merged, key, json_object_get(value));
  return merged;
}

// argv for the configured model, or NULL when AI is off or unconfigured.
// Never guesses: with nothing configured the caller falls back to the
// deterministic path rather than picking a CLI that happens to be installed.
GStrv resolve_provider(json_object *ai) {
  if (!truthy(json_get(ai, "enabled")))
    return NULL;

  g_autoptr(GStrvBuilder) argv = g_strv_builder_new();
  json_object *command = json_get(ai, "command");
  if (json_object_is_type(command, json_type_array) && json_object_array_length(command) > 0) {
    for (size_t i = 0; i < json_object_array_length(command); i++)
      g_strv_builder_take(argv, as_text(json_object_array_get_idx(command, i)));
    return g_strv_builder_end(argv);
  }

  const char *provider = json_get_str(ai, "provider");
  size_t preset = G_N_ELEMENTS(AI_PRESETS);
  for (size_t i = 0; provider && i < G_N_ELEMENTS(AI_PRESETS); i++)
    if (g_str_equal(provider, AI_PRESETS[i].name))
      preset = i;
  if (preset == G_N_ELEMENTS(AI_PRESETS))
    return NULL;

  for (size_t i = 0; AI_PRESETS[preset].argv[i]; i++)
    g_strv_builder_add(argv, AI_PRESETS[preset].argv[i]);
  json_object *model = json_get(ai, "model");
  if (g_str_equal(provider, "ollama")) {
    if (truthy(model))
      g_strv_builder_take(argv, as_text(model));
    else
      g_strv_builder_add(argv, "llama3.2");
  } else if (truthy(model)) {
    g_strv_builder_add(argv, "--model");
    g_strv_builder_take(argv, as_text(model));
  }
  if (!has(AI_PRESETS[preset].argv[0]))
    return NULL;
  return g_strv_builder_end(argv);
}

size_t ai_preset_count(void) {
  return G_N_ELEMENTS(AI_PRESETS);
}

const char *ai_preset_name(size_t i) {
  return AI_PRESETS[i].name;
}

const char *const *ai_preset_argv(size_t i) {
  return AI_PRESETS[i].argv;
}

bool is_ai_preset(const char *name) {
  for (size_t i = 0; name && i < G_N_ELEMENTS(AI_PRESETS); i++)
    if (g_str_equal(name, AI_PRESETS[i].name))
      return true;
  return false;
}

// Replace the agent block. Atomic, and with only one writer, safe. Anything
// else already in the file is kept, so a setting added beside `ai` later is
// not dropped by a change to this one.
void write_ai_settings(json_object *ai) {
  guard_paths();
  const char *path = paths()->config_path;
  g_autoptr(json_object) config = json_object_from_file(path);
  if (!json_object_is_type(config, json_type_object)) {
    g_clear_pointer(&config, json_object_put);
    config = json_object_new_object();
  }
  json_object_object_add(config, "ai", json_object_get(ai));
  g_autofree char *dir = g_path_get_dirname(path);
  g_mkdir_with_parents(dir, 0777);
  g_autofree char *text = g_strconcat(
    json_object_to_json_string_ext(config, JSON_C_TO_STRING_PRETTY | JSON_C_TO_STRING_SPACED
                                   | JSON_C_TO_STRING_NOSLASHESCAPE), "\n", NULL);
  g_autoptr(GError) error = NULL;
  if (!g_file_set_contents(path, text, -1, &error))
    die(1, "could not write %s: %s", path, error->message);
}

// Where Service.qml keeps the CLI it built: the same XDG rule the QML side
// applies, so `install` can point a PATH entry at it.
char *cache_bin_path(void) {
  const char *cache = g_getenv("XDG_CACHE_HOME");
  g_autofree char *base = cache && cache[0] == '/' ? g_strdup(cache)
                                                    : g_build_filename(g_get_home_dir(), ".cache", NULL);
  return g_build_filename(base, "omoide", "bin", "omoide", NULL);
}
